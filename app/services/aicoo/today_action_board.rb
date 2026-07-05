module Aicoo
  class TodayActionBoard
    include Rails.application.routes.url_helpers

    DESCRIPTION = "Todayは、自動改修が止まって承認が必要なもの、またはCodexでは実行できない手作業・記事作成・データ入力を、期待値順に処理する画面です。".freeze
    MODES = %w[revenue learning balanced].freeze
    APPROVAL_REQUIRED_STATUSES = %w[draft waiting_approval approved].freeze
    CODEX_QUEUE_STATUSES = %w[queued ready_for_codex sent_to_codex running].freeze
    OWNER_EXECUTION_MODES = %w[manual_operation content_creation data_operation owner_decision].freeze
    ABSTRACT_PATTERNS = [
      /検索需要があるテーマ/,
      /CVを改善/,
      /UXを改善/,
      /CTAを改善/,
      /デザインを改善/,
      /サイト改善/,
      /導線改善/,
      /記事を増やす/,
      /改善する\z/,
      /最適化する\z/,
      /強化する\z/
    ].freeze
    UNSPECIFIED_VALUES = %w[未特定 unspecified unknown].freeze

    Board = Data.define(:mode, :tabs, :items, :description)
    Tab = Data.define(:key, :label, :path, :active)
    Item = Data.define(
      :rank,
      :source_type,
      :record,
      :business_name,
      :concrete_task,
      :target,
      :expected_value_yen,
      :expected_hours,
      :expected_hourly_value_yen,
      :success_probability,
      :execution_mode,
      :execution_mode_label,
      :approval_required,
      :codex_target,
      :owner_next_step,
      :detail_url,
      :reason,
      :stopped_reason,
      :revenue_score,
      :learning_score,
      :balanced_score,
      :score
    )

    def initialize(mode: nil, limit: 10)
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "revenue"
      @limit = limit
    end

    def call
      ranked_items = candidate_items
        .sort_by { |item| [ -item.score.to_d, -item.expected_value_yen.to_i, item.business_name.to_s ] }
        .first(limit)
        .map.with_index(1) { |item, index| item.with(rank: index) }

      Board.new(mode:, tabs:, items: ranked_items, description: DESCRIPTION)
    end

    private

    attr_reader :mode, :limit

    def tabs
      [
        Tab.new(key: "revenue", label: "収益優先", path: owner_focus_path(mode: "revenue"), active: mode == "revenue"),
        Tab.new(key: "learning", label: "学習優先", path: owner_focus_path(mode: "learning"), active: mode == "learning"),
        Tab.new(key: "balanced", label: "バランス", path: owner_focus_path(mode: "balanced"), active: mode == "balanced")
      ]
    end

    def candidate_items
      ActionCandidate
        .active_for_ranking
        .includes(:business, :auto_revision_tasks)
        .order(updated_at: :desc)
        .limit(250)
        .filter_map { |candidate| build_item(candidate) }
    end

    def build_item(candidate)
      presenter = ActionCandidateEvidencePresenter.new(candidate)
      action_plan = presenter.action_plan
      execution_mode = presenter.execution_mode.to_s
      approval_task = approval_required_task(candidate)

      return unless today_eligible?(candidate, presenter, action_plan, execution_mode, approval_task)

      expected_value_yen = candidate.expected_profit_yen.to_i
      expected_hours = positive_decimal(candidate.expected_hours)
      success_probability = candidate.success_probability.to_d
      revenue_score = expected_hours.positive? ? (expected_value_yen.to_d / expected_hours * success_probability) : 0.to_d
      learning_score = learning_score_for(candidate)
      balanced_score = (revenue_score * 0.6) + (learning_score * 0.4)
      selected_score = score_for(revenue_score:, learning_score:, balanced_score:)

      Item.new(
        rank: nil,
        source_type: approval_task ? "auto_revision_task" : "action_candidate",
        record: approval_task || candidate,
        business_name: candidate.business&.name.to_s,
        concrete_task: concrete_task_for(candidate, presenter, action_plan),
        target: target_for(presenter, action_plan),
        expected_value_yen:,
        expected_hours: expected_hours.to_f,
        expected_hourly_value_yen: expected_hours.positive? ? (expected_value_yen.to_d / expected_hours).round.to_i : 0,
        success_probability:,
        execution_mode:,
        execution_mode_label: presenter.execution_mode_label,
        approval_required: approval_task.present?,
        codex_target: execution_mode == "code_revision",
        owner_next_step: owner_next_step_for(presenter, action_plan, approval_task),
        detail_url: action_workspace_path(candidate),
        reason: presenter.reason,
        stopped_reason: stopped_reason_for(approval_task),
        revenue_score: revenue_score.round(2),
        learning_score: learning_score.round(2),
        balanced_score: balanced_score.round(2),
        score: selected_score.round(2)
      )
    end

    def today_eligible?(candidate, presenter, action_plan, execution_mode, approval_task)
      return false unless required_fields_present?(candidate, presenter, action_plan, execution_mode)
      return false unless concrete_task_specific?(candidate, presenter, action_plan)
      return false if target_unspecified?(presenter, action_plan)

      owner_work = OWNER_EXECUTION_MODES.include?(execution_mode)
      approval_waiting_code_revision = execution_mode == "code_revision" && approval_task.present?

      owner_work || approval_waiting_code_revision
    end

    def required_fields_present?(candidate, presenter, action_plan, execution_mode)
      approval_task = approval_required_task(candidate)

      concrete_task_for(candidate, presenter, action_plan).present? &&
        target_for(presenter, action_plan).present? &&
        execution_mode.present? &&
        candidate.expected_hours.present? &&
        candidate.success_probability.present? &&
        owner_next_step_for(presenter, action_plan, approval_task).present? &&
        action_workspace_path(candidate).present? &&
        (approval_task.present? || presenter.execution_units?)
    end

    def concrete_task_specific?(candidate, presenter, action_plan)
      text = concrete_task_for(candidate, presenter, action_plan).to_s
      return false if text.blank?

      ABSTRACT_PATTERNS.none? { |pattern| text.match?(pattern) }
    end

    def target_unspecified?(presenter, action_plan)
      target = target_for(presenter, action_plan).to_s.strip
      target.blank? || UNSPECIFIED_VALUES.include?(target.downcase) || target.include?("未特定")
    end

    def concrete_task_for(candidate, presenter, action_plan)
      action_plan["summary"].presence ||
        candidate.metadata.to_h["concrete_task"].presence ||
        presenter.summary.presence ||
        candidate.title
    end

    def target_for(presenter, action_plan)
      action_plan["target"].presence ||
        action_plan["target_url_or_identifier"].presence ||
        presenter.target_label.presence
    end

    def owner_next_step_for(presenter, action_plan, approval_task)
      return "Codex実行前の判断を行う" if approval_task.present?

      Array(action_plan["execution_steps"]).compact_blank.first.presence ||
        action_plan["owner_next_step"].presence ||
        Array(action_plan["execution_units"]).compact_blank.first.to_h["label"].presence ||
        presenter.execution_units.first.to_h["label"].presence
    end

    def approval_required_task(candidate)
      task = candidate.auto_revision_tasks
        .reject { |auto_revision_task| auto_revision_task.status == "canceled" }
        .max_by(&:updated_at)
      return unless task
      return if CODEX_QUEUE_STATUSES.include?(task.status)
      return unless task.owner_approval_required?

      task if APPROVAL_REQUIRED_STATUSES.include?(task.status) || task.high_risk?
    end

    def stopped_reason_for(task)
      return nil unless task
      return task.approval_required_reason if task.approval_required_reason.present?

      return "高リスクのためOwner判断待ち" if task.high_risk?

      case task.status
      when "draft", "waiting_approval"
        "Codexへ進める前にOwner判断待ち"
      when "approved"
        "自動実行キュー投入前で停止中"
      else
        "自動改修が#{task.status}で停止中"
      end
    end

    def learning_score_for(candidate)
      metadata = candidate.metadata.to_h
      candidate.expected_learning_value_yen.to_i +
        numeric_metadata(metadata, "learning_value") +
        numeric_metadata(metadata, "uncertainty_reduction") +
        numeric_metadata(metadata, "uncertainty_reduction_value_yen") +
        numeric_metadata(metadata, "calibration_value") +
        numeric_metadata(metadata, "calibration_value_yen")
    end

    def score_for(revenue_score:, learning_score:, balanced_score:)
      case mode
      when "learning"
        learning_score
      when "balanced"
        balanced_score
      else
        revenue_score
      end
    end

    def positive_decimal(value)
      decimal = value.to_d
      decimal.positive? ? decimal : 0.25.to_d
    end

    def numeric_metadata(metadata, key)
      metadata[key].to_d
    rescue ArgumentError, NoMethodError
      0.to_d
    end
  end
end

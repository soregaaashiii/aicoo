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
      /CV改善\z/,
      /SEO改善\z/,
      /デザインを改善/,
      /サイト改善/,
      /導線改善/,
      /TODOを具体化/,
      /要具体化/,
      /記事を増やす/,
      /Analyzer/i
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
      :data_sources_label,
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

    def initialize(mode: nil, limit: 200)
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "revenue"
      @limit = limit
    end

    def call
      items = candidate_items
      ranked_items = items
        .sort_by { |item| [ -item.score.to_d, -item.expected_value_yen.to_i, item.business_name.to_s ] }
        .first(limit)

      ranked_items = include_missing_data_backed_businesses(items, ranked_items)
        .map.with_index(1) { |item, index| item.with(rank: index) }

      mark_filtered_items!(items, ranked_items)
      log_business_diagnostics!(items, ranked_items)

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
      items = ActionCandidate
        .active_for_ranking
        .includes(:business, :auto_revision_tasks)
        .order(updated_at: :desc)
        .limit(1_000)
        .filter_map { |candidate| build_item(candidate) }

      items
    end

    def build_item(candidate)
      presenter = ActionCandidateEvidencePresenter.new(candidate)
      action_plan = presenter.action_plan
      execution_mode = presenter.execution_mode.to_s
      approval_task = approval_required_task(candidate)

      exclusion_reason = today_exclusion_reason(candidate, execution_mode, approval_task)
      if exclusion_reason
        mark_today_exclusion!(candidate, exclusion_reason)
        return
      end

      expected_value_yen = candidate.expected_profit_yen.to_i
      expected_hours = positive_decimal(candidate.expected_hours)
      success_probability = candidate.success_probability.to_d
      concrete_task = concrete_task_for(candidate, presenter, action_plan)
      target = target_for(presenter, action_plan)
      owner_next_step = owner_next_step_for(presenter, action_plan, approval_task)

      if concrete_task.blank?
        mark_today_exclusion!(candidate, "missing_concrete_task")
        return
      end

      if target.blank?
        mark_today_exclusion!(candidate, "missing_target")
        return
      end

      if owner_next_step.blank?
        mark_today_exclusion!(candidate, "missing_owner_next_step")
        return
      end

      revenue_score = valuation_adjusted_revenue_score(
        candidate,
        expected_value_yen:,
        expected_hours:,
        success_probability:
      )
      learning_score = learning_score_for(candidate)
      balanced_score = (revenue_score * 0.6) + (learning_score * 0.4)
      selected_score = score_for(revenue_score:, learning_score:, balanced_score:)

      mark_today_included!(candidate)
      Item.new(
        rank: nil,
        source_type: approval_task ? "auto_revision_task" : "action_candidate",
        record: approval_task || candidate,
        business_name: candidate.business&.name.to_s,
        concrete_task:,
        target:,
        expected_value_yen:,
        expected_hours: expected_hours.to_f,
        expected_hourly_value_yen: expected_hours.positive? ? (expected_value_yen.to_d / expected_hours).round.to_i : 0,
        success_probability:,
        execution_mode:,
        execution_mode_label: presenter.execution_mode_label,
        data_sources_label: presenter.source_label,
        approval_required: approval_task.present?,
        codex_target: execution_mode == "code_revision",
        owner_next_step:,
        detail_url: action_workspace_path(candidate),
        reason: presenter.reason,
        stopped_reason: stopped_reason_for(approval_task),
        revenue_score: revenue_score.round(2),
        learning_score: learning_score.round(2),
        balanced_score: balanced_score.round(2),
        score: selected_score.round(2)
      )
    end

    def today_exclusion_reason(candidate, execution_mode, approval_task)
      return "inactive_business" if candidate.business.blank? || candidate.business.resource_status == "archived"
      return "no_score" unless minimum_fields_present?(candidate, execution_mode)
      return "fallback_action" if candidate.metadata.to_h["today_fallback"]
      return "needs_refinement" if candidate.metadata.to_h["concretization_status"] == "needs_refinement"
      return "abstract_concrete_task" unless concrete_text_allowed?(candidate)
      return "external_data_source_disallowed" if external_data_source_used_for_existing_business?(candidate)

      owner_work = OWNER_EXECUTION_MODES.include?(execution_mode)
      approval_waiting_code_revision = execution_mode == "code_revision" && approval_task.present?

      return nil if owner_work || approval_waiting_code_revision
      return "code_revision_auto_executable" if execution_mode == "code_revision"

      "unsupported_execution_mode"
    end

    def minimum_fields_present?(candidate, execution_mode)
      execution_mode.present? &&
        candidate.expected_hours.present? &&
        candidate.success_probability.present? &&
        action_workspace_path(candidate).present?
    end

    def concrete_task_for(candidate, presenter, action_plan)
      text = action_plan["summary"].presence ||
        candidate.metadata.to_h["concrete_task"].presence ||
        candidate.metadata.to_h.dig("decision", "selected", "concrete_task").presence ||
        candidate.title.presence

      return nil if text.blank?
      return nil if ABSTRACT_PATTERNS.any? { |pattern| text.match?(pattern) }

      text
    end

    def target_for(presenter, action_plan)
      target = action_plan["target"].presence ||
        action_plan["target_url_or_identifier"].presence ||
        presenter.action_plan["target"].presence ||
        presenter.action_plan["target_url_or_identifier"].presence ||
        presenter.target_label.presence

      return nil if target.to_s.strip.blank?
      return nil if UNSPECIFIED_VALUES.include?(target.to_s.downcase) || target.to_s.include?("未特定")

      target
    end

    def owner_next_step_for(presenter, action_plan, approval_task)
      return "Codex実行前の判断を行う" if approval_task.present?

      Array(action_plan["execution_steps"]).compact_blank.first.presence ||
        action_plan["owner_next_step"].presence ||
        Array(action_plan["execution_units"]).compact_blank.first.to_h["label"].presence ||
        presenter.execution_units.first.to_h["label"].presence
    end

    def concrete_text_allowed?(candidate)
      metadata = candidate.metadata.to_h
      values = [
        metadata.dig("action_plan", "summary"),
        metadata["concrete_task"],
        metadata.dig("decision", "selected", "concrete_task"),
        candidate.title
      ].compact_blank
      return false if values.empty?

      values.none? { |value| ABSTRACT_PATTERNS.any? { |pattern| value.to_s.match?(pattern) } }
    end

    def external_data_source_used_for_existing_business?(candidate)
      return false if Aicoo::DataSourcePolicy.for(candidate.business).exploration_business?

      data_sources = Array(candidate.metadata.to_h["data_sources_used"]) +
        Array(candidate.metadata.to_h.dig("evidence", "source")) +
        Array(candidate.metadata.to_h["evidence_sources"]) +
        Array(candidate.metadata.to_h["data_sources"])
      (data_sources.map(&:to_s).map(&:downcase) & %w[serp x reddit news]).any?
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

    def include_missing_data_backed_businesses(items, ranked_items)
      ranked_business_ids = ranked_items.map { |item| item.record.business_id }.compact.to_set
      missing_items = items
        .select { |item| analysis_data_available_for?(item.record.business) && ranked_business_ids.exclude?(item.record.business_id) }
        .group_by { |item| item.record.business_id }
        .values
        .map { |business_items| business_items.max_by(&:score) }

      (ranked_items + missing_items).uniq { |item| "#{item.source_type}:#{item.record.id}" }
    end

    def today_visible_businesses
      Business.real_businesses.where(resource_status: nil)
        .or(Business.real_businesses.where(resource_status: %w[active watch paused]))
    end

    def analysis_data_available_for?(business)
      return false unless business

      today = Date.current
      business.business_metric_dailies.where(recorded_on: (today - 29)..today).exists? ||
        business.business_activity_logs.where(occurred_at: 30.days.ago..Time.current).exists?
    end

    def mark_today_exclusion!(candidate, reason)
      metadata = candidate.metadata.to_h
      return if metadata["today_exclusion_reason"] == reason

      candidate.update_columns(
        metadata: metadata.merge(
          "today_exclusion_reason" => reason,
          "today_exclusion_checked_at" => Time.current.iso8601,
          "today_mode" => mode
        ),
        updated_at: Time.current
      )
    end

    def mark_today_included!(candidate)
      metadata = candidate.metadata.to_h
      return if metadata["today_exclusion_reason"].blank? && metadata["today_included_at"].present?

      candidate.update_columns(
        metadata: metadata.except("today_exclusion_reason").merge(
          "today_included_at" => Time.current.iso8601,
          "today_mode" => mode
        ),
        updated_at: Time.current
      )
    end

    def mark_filtered_items!(items, ranked_items)
      ranked_ids = ranked_items.map { |item| item.record.id }.to_set
      items.each do |item|
        next if ranked_ids.include?(item.record.id)

        mark_today_exclusion!(item.record, "filtered_by_tab")
      end
    end

    def log_business_diagnostics!(items, ranked_items)
      grouped_items = items.group_by { |item| item.record.business_id }
      ranked_grouped_items = ranked_items.group_by { |item| item.record.business_id }

      Business.real_businesses.find_each do |business|
        active_candidates = business.action_candidates.active_for_ranking.limit(250).to_a
        business_items = grouped_items[business.id] || []
        ranked_business_items = ranked_grouped_items[business.id] || []
        diagnostics = {
          event: "today_business_diagnostics",
          mode:,
          business_id: business.id,
          business_name: business.name,
          business_type: business.business_type,
          active: business.resource_status,
          gsc_candidate_count: gsc_candidate_count_for(business, active_candidates),
          ga4_candidate_count: ga4_candidate_count_for(business, active_candidates),
          opportunity_count: opportunity_count_for(active_candidates),
          strategy_count: strategy_count_for(active_candidates),
          action_candidate_count: active_candidates.size,
          today_candidate_count: ranked_business_items.size,
          revenue_score: business_items.map(&:revenue_score).compact.max,
          learning_score: business_items.map(&:learning_score).compact.max,
          balanced_score: business_items.map(&:balanced_score).compact.max,
          execution_mode: active_candidates.map { |candidate| candidate.metadata.to_h["execution_mode"].presence || candidate.execution_mode }.compact.uniq,
          status: active_candidates.map(&:status).compact.uniq,
          generation_source: active_candidates.map(&:generation_source).compact.uniq,
          exclusion_reason: active_candidates.map { |candidate| candidate.metadata.to_h["today_exclusion_reason"] }.compact.uniq
        }
        Rails.logger.info(diagnostics.to_json)
      end
    end

    def gsc_candidate_count_for(business, candidates)
      metric_count = business.business_metric_dailies.where("impressions > 0 OR clicks > 0").count
      candidate_count = candidates.count { |candidate| candidate_metadata_sources(candidate).include?("gsc") }
      metric_count + candidate_count
    end

    def ga4_candidate_count_for(business, candidates)
      metric_count = business.business_metric_dailies.where("sessions > 0 OR pageviews > 0").count
      candidate_count = candidates.count { |candidate| candidate_metadata_sources(candidate).include?("ga4") }
      metric_count + candidate_count
    end

    def opportunity_count_for(candidates)
      candidates.count { |candidate| candidate.metadata.to_h["opportunity"].present? || candidate.metadata.to_h["opportunity_type"].present? }
    end

    def strategy_count_for(candidates)
      candidates.sum do |candidate|
        metadata = candidate.metadata.to_h
        metadata.dig("decision", "candidate_count").to_i.presence ||
          Array(metadata.dig("strategy_ranking", "rejected")).size + (metadata.dig("strategy_ranking", "adopted").present? ? 1 : 0)
      end
    end

    def candidate_metadata_sources(candidate)
      metadata = candidate.metadata.to_h
      [
        metadata.dig("evidence", "source"),
        metadata["evidence_sources"],
        metadata.dig("opportunity", "supporting_metrics", "source")
      ].flatten.compact.map(&:to_s)
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

    def valuation_adjusted_revenue_score(candidate, expected_value_yen:, expected_hours:, success_probability:)
      return 0.to_d unless expected_hours.positive?

      base_score = expected_value_yen.to_d / expected_hours * success_probability
      value_model = candidate.metadata.to_h["value_model"].to_h
      return base_score if value_model.blank?

      confidence = decimal_value(value_model["confidence"], fallback: success_probability)
      evidence_factor = { "high" => 1.0.to_d, "medium" => 0.7.to_d, "low" => 0.35.to_d }.fetch(value_model["evidence_level"].to_s, 0.35.to_d)
      outlier_penalty = [ decimal_value(value_model["outlier_ratio"], fallback: 1) / 10, 1.to_d ].max
      cost_factor = if candidate.cost_yen.to_d.positive? && expected_value_yen.to_d.positive?
        [ 1.to_d + (candidate.cost_yen.to_d / expected_value_yen.to_d), 1.5.to_d ].min
      else
        1.to_d
      end

      base_score * confidence * evidence_factor / outlier_penalty / cost_factor
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

    def decimal_value(value, fallback:)
      value.to_d
    rescue ArgumentError, NoMethodError
      fallback.to_d
    end
  end
end

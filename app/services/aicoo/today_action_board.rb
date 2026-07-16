module Aicoo
  class TodayActionBoard
    include Rails.application.routes.url_helpers

    DESCRIPTION = "Todayは、未実行の有効な施策を、施策期待値が高い順に処理する画面です。".freeze
    MODES = %w[revenue learning balanced].freeze
    APPROVAL_REQUIRED_STATUSES = %w[draft waiting_approval approved].freeze
    CODEX_QUEUE_STATUSES = %w[queued ready_for_codex sent_to_codex running].freeze
    PER_PAGE = Aicoo::ActionExpectedValueRanking::DEFAULT_PER_PAGE
    HIGH_VALUE_REVIEW_THRESHOLD_YEN = 1_000_000
    DAILY_RUN_MINIMUM_AVOIDED_LOSS_YEN = 15_000
    DAILY_RUN_STANDARD_LOSS_PER_BUSINESS_YEN = 5_000
    DAILY_RUN_STANDARD_NEW_BUSINESS_LOSS_PER_BUSINESS_YEN = 1_500
    DAILY_RUN_STANDARD_LEARNING_LOSS_PER_BUSINESS_YEN = 1_000
    DAILY_RUN_OWNER_HOURLY_COST_YEN = 6_000
    DAILY_RUN_REPAIR_COST_YEN = 10_000
    ARTICLE_PATH_PATTERN = %r{\A/articles/([^/?#]+)}.freeze
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

    Board = Data.define(
      :mode,
      :tabs,
      :items,
      :description,
      :total_count,
      :current_page,
      :total_pages,
      :per_page,
      :offset,
      :page_param
    )
    Tab = Data.define(:key, :label, :path, :active)
    DailyRunValuation = Data.define(
      :avoided_loss_yen,
      :expected_value_if_no_action_yen,
      :expected_value_if_action_yen,
      :action_expected_value_delta_yen,
      :final_expected_value_yen,
      :recovery_success_probability,
      :repair_cost_yen,
      :human_cost_yen,
      :impact_days,
      :unresolved_run_count,
      :impacted_business_count,
      :calculation_method,
      :estimate_confidence,
      :missing_inputs,
      :daily_improvement_value_yen,
      :daily_new_business_value_yen,
      :daily_learning_loss_yen,
      :recurrence_expected_loss_yen
    )
    Item = Data.define(
      :stable_id,
      :rank,
      :source_type,
      :record,
      :priority,
      :business_name,
      :concrete_task,
      :target,
      :expected_value_yen,
      :expected_value_if_no_action_yen,
      :expected_value_if_action_yen,
      :execution_cost_yen,
      :action_expected_value_delta_yen,
      :valuation_period_days,
      :calculation_method,
      :confidence,
      :valuation_status,
      :expected_hours,
      :expected_hourly_value_yen,
      :success_probability,
      :execution_mode,
      :execution_mode_label,
      :data_sources_label,
      :approval_required,
      :codex_target,
      :owner_next_step,
      :planned_url,
      :detail_url,
      :reason,
      :stopped_reason,
      :group_count,
      :group_summary,
      :revenue_score,
      :learning_score,
      :balanced_score,
      :score
    )

    def initialize(mode: nil, page: nil, page_param: :today_actions_page, per_page: PER_PAGE)
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "revenue"
      @page = page
      @page_param = page_param.to_sym
      @per_page = per_page
    end

    def call
      Aicoo::MemoryDiagnostics.measure("Aicoo::TodayActionBoard#call", context: memory_context) do
        items = candidate_items
        ranking = ActionExpectedValueRanking.new(
          items: select_today_items(items),
          mode:,
          page:,
          per_page:
        ).call

        log_business_diagnostics!(items, ranking.items)

        Board.new(
          mode:,
          tabs:,
          items: ranking.items,
          description: DESCRIPTION,
          total_count: ranking.total_count,
          current_page: ranking.current_page,
          total_pages: ranking.total_pages,
          per_page: ranking.per_page,
          offset: ranking.offset,
          page_param:
        )
      end
    end

    private

    attr_reader :mode, :page, :page_param, :per_page

    def memory_context(extra = {})
      {
        mode:,
        page: page.presence,
        page_param:,
        per_page:
      }.merge(extra).compact
    end

    def tabs
      [
        Tab.new(key: "revenue", label: "収益優先", path: owner_focus_path(mode: "revenue"), active: mode == "revenue"),
        Tab.new(key: "learning", label: "学習優先", path: owner_focus_path(mode: "learning"), active: mode == "learning"),
        Tab.new(key: "balanced", label: "バランス", path: owner_focus_path(mode: "balanced"), active: mode == "balanced")
      ]
    end

    def candidate_items
      Aicoo::MemoryDiagnostics.measure("Aicoo::TodayActionBoard#candidate_items", context: memory_context) do
        daily_run_issue_items +
          action_candidate_items +
          new_business_items
      end
    end

    def select_today_items(items)
      items.uniq(&:stable_id)
    end

    def action_candidate_items
      Aicoo::MemoryDiagnostics.measure("Aicoo::TodayActionBoard#action_candidate_items", context: memory_context) do
        ActionCandidate
          .active_for_ranking
          .includes(:business, :action_result, :action_execution, :auto_revision_tasks)
          .order(updated_at: :desc)
          .filter_map { |candidate| build_item(candidate) }
      end
    end

    def build_item(candidate)
      presenter = ActionCandidateEvidencePresenter.new(candidate)
      action_plan = presenter.action_plan
      execution_mode = presenter.execution_mode.to_s
      approval_task = approval_required_task(candidate)

      exclusion_reason = today_exclusion_reason(candidate, execution_mode, approval_task)
      if exclusion_reason
        mark_today_exclusion!(candidate, exclusion_reason, detected_target_url: detected_target_url_for(candidate))
        return
      end

      valuation = action_candidate_valuation(candidate)
      expected_value_yen = valuation.fetch(:action_expected_value_delta_yen)
      expected_hours = positive_decimal(candidate.expected_hours)
      success_probability = candidate.success_probability.to_d
      raw_concrete_task = concrete_task_for(candidate, presenter, action_plan)
      raw_target = target_for(candidate, presenter, action_plan)
      planned_url = planned_url_for(candidate)
      raw_owner_next_step = owner_next_step_for(presenter, action_plan, approval_task)
      concrete_task = raw_concrete_task.presence || candidate.title.presence || "施策内容を確認する"
      target = new_content_action?(candidate) ? "未作成" : (raw_target.presence || detected_target_url_for(candidate).presence || "対象未特定")
      owner_next_step = raw_owner_next_step.presence || "詳細を確認する"
      quality_warnings = today_quality_warnings_for(
        candidate,
        execution_mode,
        concrete_task: raw_concrete_task,
        target: raw_target,
        owner_next_step: raw_owner_next_step,
        valuation:
      )

      revenue_score = valuation_adjusted_revenue_score(
        candidate,
        expected_value_yen:,
        expected_hours:,
        success_probability:
      )
      learning_score = learning_score_for(candidate)
      balanced_score = (revenue_score * 0.6) + (learning_score * 0.4)
      selected_score = score_for(revenue_score:, learning_score:, balanced_score:)

      mark_today_included!(candidate, quality_warnings:)
      Item.new(
        stable_id: "action_candidate:#{candidate.id}",
        rank: nil,
        source_type: approval_task ? "auto_revision_task" : "action_candidate",
        record: approval_task || candidate,
        priority: approval_task ? "critical" : "improvement",
        business_name: candidate.business&.name.to_s,
        concrete_task:,
        target:,
        expected_value_yen:,
        expected_value_if_no_action_yen: valuation.fetch(:expected_value_if_no_action_yen),
        expected_value_if_action_yen: valuation.fetch(:expected_value_if_action_yen),
        execution_cost_yen: valuation.fetch(:execution_cost_yen),
        action_expected_value_delta_yen: valuation.fetch(:action_expected_value_delta_yen),
        valuation_period_days: valuation.fetch(:valuation_period_days),
        calculation_method: valuation.fetch(:calculation_method),
        confidence: success_probability,
        valuation_status: valuation.fetch(:valuation_status),
        expected_hours: expected_hours.to_f,
        expected_hourly_value_yen: expected_hours.positive? ? (expected_value_yen.to_d / expected_hours).round.to_i : 0,
        success_probability:,
        execution_mode:,
        execution_mode_label: presenter.execution_mode_label,
        data_sources_label: presenter.source_label,
        approval_required: approval_task.present?,
        codex_target: execution_mode == "code_revision",
        owner_next_step:,
        planned_url:,
        detail_url: action_workspace_path(candidate),
        reason: presenter.reason,
        stopped_reason: today_warning_text(stopped_reason_for(approval_task), quality_warnings),
        group_count: 1,
        group_summary: nil,
        revenue_score: revenue_score.round(2),
        learning_score: learning_score.round(2),
        balanced_score: balanced_score.round(2),
        score: selected_score.round(2)
      )
    end

    def daily_run_issue_items
      Aicoo::MemoryDiagnostics.measure("Aicoo::TodayActionBoard#daily_run_issue_items", context: memory_context) do
        runs = AicooDailyRun
          .actual_runs
          .where(created_at: 7.days.ago..Time.current)
          .where(status: %w[failed partial_failed stuck])
          .includes(:aicoo_daily_run_steps)
          .recent
          .limit(100)
          .to_a

        runs.group_by { |run| daily_run_dedupe_key(run) }
            .values
            .reject { |grouped_runs| daily_run_issue_recovered?(grouped_runs) }
            .map { |grouped_runs| build_daily_run_issue_item(grouped_runs) }
      end
    end

    def build_daily_run_issue_item(runs)
      sorted = runs.sort_by { |run| [ run.started_at || run.created_at, run.id ] }
      latest = sorted.last
      oldest = sorted.first
      step = daily_run_last_step(latest)
      step_name = step&.step_name.presence || "unknown_step"
      reason = daily_run_reason(latest, step)
      count = runs.size
      valuation = daily_run_issue_valuation(sorted, latest:)
      status_label = latest.status == "partial_failed" ? "一部失敗" : "停止"
      persist_daily_run_valuation!(step, valuation)

      Item.new(
        stable_id: "daily_run_issue:#{daily_run_dedupe_key(latest)}",
        rank: nil,
        source_type: "daily_run_issue",
        record: latest,
        priority: latest.status == "partial_failed" ? "high" : "critical",
        business_name: "AICOO",
        concrete_task: "Daily Runが #{step_name} で継続#{status_label}",
        target: "影響日数 #{valuation.impact_days}日 / 影響Business #{valuation.impacted_business_count}件 / 該当Run #{count}件 / 最新Run ##{latest.id}",
        expected_value_yen: valuation.action_expected_value_delta_yen,
        expected_value_if_no_action_yen: valuation.expected_value_if_no_action_yen,
        expected_value_if_action_yen: valuation.expected_value_if_action_yen,
        execution_cost_yen: valuation.repair_cost_yen,
        action_expected_value_delta_yen: valuation.action_expected_value_delta_yen,
        valuation_period_days: valuation.impact_days,
        calculation_method: valuation.calculation_method,
        confidence: valuation.recovery_success_probability,
        valuation_status: valuation.action_expected_value_delta_yen.positive? ? "positive" : "negative",
        expected_hours: 1.0,
        expected_hourly_value_yen: valuation.action_expected_value_delta_yen,
        success_probability: valuation.recovery_success_probability,
        execution_mode: "system_recovery",
        execution_mode_label: "障害対応",
        data_sources_label: "Daily Run",
        approval_required: false,
        codex_target: false,
        owner_next_step: "#{step_name}を修復する",
        planned_url: nil,
        detail_url: aicoo_daily_run_path(latest, anchor: "step-breakdown"),
        reason: "#{reason} / 損失回避額 #{valuation.avoided_loss_yen.to_fs(:delimited)}円 / 復旧成功率 #{(valuation.recovery_success_probability * 100).round}% / 修正コスト #{valuation.repair_cost_yen.to_fs(:delimited)}円",
        stopped_reason: "影響日数 #{valuation.impact_days}日 / 影響Business #{valuation.impacted_business_count}件 / 同一障害 #{count}件 / 算定方法 #{valuation.calculation_method} / 信頼度 #{valuation.estimate_confidence} / 最新Run ##{latest.id} / 最古Run ##{oldest.id}",
        group_count: count,
        group_summary: "影響日数 #{valuation.impact_days}日 / 同一障害 #{count}件 / 損失回避額 #{valuation.avoided_loss_yen.to_fs(:delimited)}円",
        revenue_score: valuation.action_expected_value_delta_yen,
        learning_score: valuation.daily_learning_loss_yen,
        balanced_score: ((valuation.action_expected_value_delta_yen.to_d * 0.6) + (valuation.daily_learning_loss_yen.to_d * 0.4)).round(2),
        score: score_for(
          revenue_score: valuation.action_expected_value_delta_yen.to_d,
          learning_score: valuation.daily_learning_loss_yen.to_d,
          balanced_score: (valuation.action_expected_value_delta_yen.to_d * 0.6) + (valuation.daily_learning_loss_yen.to_d * 0.4)
        ).round(2)
      )
    end

    def new_business_items
      Aicoo::MemoryDiagnostics.measure("Aicoo::TodayActionBoard#new_business_items", context: memory_context) do
        businesses = Business
          .real_businesses
          .where(status: %w[discovered draft exploring])
          .where(resource_status: %w[active watch])
          .where("created_by_aicoo = ? OR business_type = ?", true, "exploration")
          .order(created_at: :desc)
          .limit(100)
          .select { |business| new_business_today_actionable?(business) }

        businesses.group_by { |business| new_business_group_key(business) }
                  .values
                  .map { |group| build_new_business_item(group) }
      end
    end

    def build_new_business_item(group)
      business = group.max_by { |item| new_business_score(item) }
      business_value = Aicoo::BusinessExpectedValue.call(business)
      valuation = new_business_valuation(business, business_value)
      expected_value_yen = valuation.fetch(:action_expected_value_delta_yen)
      expected_hours = positive_decimal(business.metadata.to_h["expected_hours"].presence || 2)
      success_probability = valuation.fetch(:confidence)
      revenue_score = expected_hours.positive? ? expected_value_yen.to_d / expected_hours * success_probability : 0.to_d
      learning_score = numeric_metadata(business.metadata.to_h, "learning_value")
      balanced_score = (revenue_score * 0.6) + (learning_score * 0.4)

      group_count = group.size
      title = group_count > 1 ? "#{new_business_group_label(business)}関連の検証事業を整理する" : "#{business.name} の検証を進める"

      Item.new(
        stable_id: "new_business_group:#{new_business_group_key(business)}",
        rank: nil,
        source_type: "new_business",
        record: business,
        priority: "new_business",
        business_name: business.name,
        concrete_task: title,
        target: group_count > 1 ? "代表Business ##{business.id} / 類似候補 #{group_count}件" : business.name,
        expected_value_yen:,
        expected_value_if_no_action_yen: valuation.fetch(:expected_value_if_no_action_yen),
        expected_value_if_action_yen: valuation.fetch(:expected_value_if_action_yen),
        execution_cost_yen: valuation.fetch(:execution_cost_yen),
        action_expected_value_delta_yen: valuation.fetch(:action_expected_value_delta_yen),
        valuation_period_days: valuation.fetch(:valuation_period_days),
        calculation_method: valuation.fetch(:calculation_method),
        confidence: valuation.fetch(:confidence),
        valuation_status: valuation.fetch(:valuation_status),
        expected_hours: expected_hours.to_f,
        expected_hourly_value_yen: expected_hours.positive? ? (expected_value_yen.to_d / expected_hours).round.to_i : 0,
        success_probability:,
        execution_mode: "owner_decision",
        execution_mode_label: "新規事業検証",
        data_sources_label: "SERP / 新規事業",
        approval_required: false,
        codex_target: false,
        owner_next_step: business.metadata.to_h["owner_next_step"].presence || business.metadata.to_h["next_action"].presence || "代表案を確認し、残りを統合またはアーカイブする",
        planned_url: nil,
        detail_url: owner_new_business_pipeline_path(selected: "business:#{business.id}"),
        reason: business.metadata.to_h["reason"].presence || "探索中の新規事業です。算定方法: #{business_value.calculation_method}",
        stopped_reason: business.launched? ? nil : "検証前状態です",
        group_count: group_count,
        group_summary: group_count > 1 ? "類似候補 #{group_count}件" : nil,
        revenue_score: revenue_score.round(2),
        learning_score: learning_score.round(2),
        balanced_score: balanced_score.round(2),
        score: score_for(revenue_score:, learning_score:, balanced_score:).round(2)
      )
    end

    def today_exclusion_reason(candidate, execution_mode, approval_task)
      return "executed" if candidate.executed?
      return "inactive_business" if candidate.business.blank? || candidate.business.deleted? || candidate.business.resource_status == "archived"
      return "invalid_status" if candidate.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)
      return "blocked_by_prerequisite" if candidate.metadata.to_h["blocked"] && candidate.metadata.to_h["prerequisite_action_candidate_id"].present?
      return "external_reference_target" if external_target_url_for_existing_business?(candidate)
      return "invalid_target" if invalid_target_path_reason(candidate).present?
      return "proposed_new_used_as_existing_target" if existing_page_improvement?(candidate) && proposed_new_target?(candidate)

      nil
    end

    def minimum_fields_present?(candidate, execution_mode)
      execution_mode.present? &&
        candidate.expected_hours.present? &&
        candidate.success_probability.present? &&
        action_workspace_path(candidate).present?
    end

    def today_quality_warnings_for(candidate, execution_mode, concrete_task:, target:, owner_next_step:, valuation:)
      warnings = []
      warnings << "実行方法要確認" if execution_mode.blank?
      warnings << "期待値要確認" if valuation.fetch(:valuation_status) == "unvalued"
      warnings << "代替候補" if candidate.metadata.to_h["today_fallback"]
      warnings << "次の行動要具体化" if candidate.metadata.to_h["concretization_status"] == "needs_refinement"
      warnings << "作業名要確認" if concrete_task.blank? || !concrete_text_allowed?(candidate)
      warnings << "対象未特定" if target.blank?
      warnings << "次の行動要具体化" if owner_next_step.blank?
      warnings << "外部データ由来" if external_data_source_used_for_existing_business?(candidate)
      warnings << "外部URL" if external_target_url_for_existing_business?(candidate)
      warnings << warning_label_for_invalid_target_path(candidate) if invalid_target_path_reason(candidate).present?
      warnings << "期待値要確認" if unrealistic_expected_profit?(candidate)
      warnings.compact.uniq
    end

    def warning_label_for_invalid_target_path(candidate)
      case invalid_target_path_reason(candidate)
      when "target_type_mismatch"
        "対象URL要確認"
      when "missing_slug", "invalid_target_path"
        "対象URL要確認"
      else
        "対象要確認"
      end
    end

    def today_warning_text(base_reason, warnings)
      parts = []
      parts << base_reason if base_reason.present?
      parts << "警告: #{warnings.join(' / ')}" if warnings.present?
      parts.join(" / ").presence
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

    def target_for(candidate, presenter, action_plan)
      return "未作成" if new_content_action?(candidate)

      target = action_plan["target"].presence ||
        action_plan["target_url_or_identifier"].presence ||
        presenter.action_plan["target"].presence ||
        presenter.action_plan["target_url_or_identifier"].presence ||
        presenter.target_label.presence

      return nil if target.to_s.strip.blank?
      return nil if UNSPECIFIED_VALUES.include?(target.to_s.downcase) || target.to_s.include?("未特定")

      target
    end

    def planned_url_for(candidate)
      metadata = candidate.metadata.to_h
      metadata["planned_url"].presence ||
        metadata["proposed_url"].presence ||
        metadata["recommended_url"].presence ||
        metadata.dig("article_candidate", "recommended_url").presence
    end

    def new_content_action?(candidate)
      return false unless candidate

      metadata = candidate.metadata.to_h
      candidate.action_type.to_s.in?(%w[new_article_candidate article_create seo_article]) ||
        metadata["url_classification"].to_s == "proposed_new" ||
        metadata["target_url_type"].to_s == "proposed_new" ||
        metadata["planned_url"].present? ||
        metadata["work_type"].to_s.in?(%w[new_article new_lp new_category article_create])
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
      ranked_business_ids = ranked_items.filter_map { |item| item.record.business_id if item.record.respond_to?(:business_id) }.to_set
      missing_items = items
        .select { |item| item.record.respond_to?(:business) && analysis_data_available_for?(item.record.business) && ranked_business_ids.exclude?(item.record.business_id) }
        .group_by { |item| item.record.business_id }
        .values
        .map { |business_items| business_items.max_by(&:score) }

      (ranked_items + missing_items).uniq(&:stable_id)
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

    def mark_today_exclusion!(candidate, reason, detected_target_url: nil)
      metadata = candidate.metadata.to_h
      return if metadata["today_exclusion_reason"] == reason && metadata["detected_target_url"].to_s == detected_target_url.to_s

      candidate.update_columns(
        metadata: metadata.merge(
          "today_exclusion_reason" => reason,
          "today_excluded_at" => Time.current.iso8601,
          "today_exclusion_checked_at" => Time.current.iso8601,
          "today_mode" => mode,
          "detected_target_url" => detected_target_url
        ),
        updated_at: Time.current
      )
    end

    def mark_today_included!(candidate, quality_warnings: [])
      metadata = candidate.metadata.to_h
      return if metadata["today_exclusion_reason"].blank? &&
        metadata["today_included_at"].present? &&
        Array(metadata["today_quality_warnings"]) == quality_warnings

      candidate.update_columns(
        metadata: metadata.except("today_exclusion_reason", "today_excluded_at", "detected_target_url").merge(
          "today_included_at" => Time.current.iso8601,
          "today_mode" => mode,
          "today_quality_warnings" => quality_warnings
        ),
        updated_at: Time.current
      )
    end

    def mark_filtered_items!(items, ranked_items)
      ranked_ids = ranked_items.select { |item| item.record.is_a?(ActionCandidate) }.map { |item| item.record.id }.to_set
      items.each do |item|
        next unless item.record.is_a?(ActionCandidate)
        next if ranked_ids.include?(item.record.id)

        mark_today_exclusion!(item.record, "filtered_by_tab")
      end
    end

    def log_business_diagnostics!(items, ranked_items)
      grouped_items = items.select { |item| item.record.respond_to?(:business_id) }.group_by { |item| item.record.business_id }
      ranked_grouped_items = ranked_items.select { |item| item.record.respond_to?(:business_id) }.group_by { |item| item.record.business_id }

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

    def action_candidate_valuation(candidate)
      metadata = candidate.metadata.to_h
      gross_action_value_yen = first_present_integer(
        metadata["expected_value_if_action_yen"],
        metadata.dig("action_value_model", "expected_value_if_action_yen"),
        metadata.dig("value_model", "expected_value_if_action_yen")
      )
      gross_action_value_yen = candidate_today_expected_value_yen(candidate) if gross_action_value_yen.nil?

      no_action_yen = first_present_integer(
        metadata["expected_value_if_no_action_yen"],
        metadata.dig("action_value_model", "expected_value_if_no_action_yen"),
        metadata.dig("value_model", "expected_value_if_no_action_yen")
      ) || 0
      execution_cost_yen = first_present_integer(
        metadata["execution_cost_yen"],
        metadata.dig("action_value_model", "execution_cost_yen"),
        metadata.dig("value_model", "execution_cost_yen")
      )
      execution_cost_yen = candidate.cost_yen.to_i if execution_cost_yen.nil?
      delta_yen = gross_action_value_yen.to_i - no_action_yen.to_i - execution_cost_yen.to_i

      {
        expected_value_if_no_action_yen: no_action_yen.to_i,
        expected_value_if_action_yen: gross_action_value_yen.to_i,
        execution_cost_yen: execution_cost_yen.to_i,
        action_expected_value_delta_yen: delta_yen,
        valuation_period_days: first_present_integer(metadata["valuation_period_days"], metadata.dig("action_value_model", "valuation_period_days")) || 90,
        calculation_method: metadata.dig("action_value_model", "calculation_method").presence || metadata.dig("business_value_model", "calculation_method").presence || "action_counterfactual_delta",
        confidence: confidence_value_for(candidate),
        valuation_status: valuation_status_for(delta_yen)
      }
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

    def daily_run_issue_valuation(runs, latest:)
      impact_days = [ runs.map(&:target_date).compact.uniq.size, 1 ].max
      impacted_business_count = active_impacted_business_count
      missing_inputs = []

      step_name = daily_run_last_step(latest)&.step_name.to_s

      daily_improvement_value_yen = step_adjusted_daily_improvement_value_yen(step_name)
      unless daily_improvement_value_yen.positive?
        missing_inputs << "recent_action_candidate_value"
        daily_improvement_value_yen = impacted_business_count * DAILY_RUN_STANDARD_LOSS_PER_BUSINESS_YEN
      end

      daily_new_business_value_yen = step_adjusted_daily_new_business_value_yen(step_name)
      unless daily_new_business_value_yen.positive?
        missing_inputs << "recent_new_business_value"
        daily_new_business_value_yen = impacted_business_count * DAILY_RUN_STANDARD_NEW_BUSINESS_LOSS_PER_BUSINESS_YEN
      end

      daily_learning_loss_yen = step_adjusted_daily_learning_value_yen(step_name)
      unless daily_learning_loss_yen.positive?
        missing_inputs << "recent_learning_value"
        daily_learning_loss_yen = impacted_business_count * DAILY_RUN_STANDARD_LEARNING_LOSS_PER_BUSINESS_YEN
      end

      human_cost_yen = estimated_daily_run_human_cost_yen(runs)
      recurrence_expected_loss_yen = ((daily_improvement_value_yen + daily_new_business_value_yen + daily_learning_loss_yen).to_d * 0.2).round
      avoided_loss_yen = [
        ((daily_improvement_value_yen + daily_new_business_value_yen + daily_learning_loss_yen) * impact_days) + human_cost_yen + recurrence_expected_loss_yen,
        DAILY_RUN_MINIMUM_AVOIDED_LOSS_YEN
      ].max
      recovery_success_probability = daily_run_recovery_success_probability(latest, runs)
      repair_cost_yen = DAILY_RUN_REPAIR_COST_YEN
      expected_value_if_no_action_yen = -avoided_loss_yen
      expected_value_if_action_yen = (expected_value_if_no_action_yen.to_d * (1 - recovery_success_probability)).round
      action_expected_value_delta_yen = expected_value_if_action_yen - expected_value_if_no_action_yen - repair_cost_yen
      final_expected_value_yen = action_expected_value_delta_yen

      DailyRunValuation.new(
        avoided_loss_yen:,
        expected_value_if_no_action_yen:,
        expected_value_if_action_yen:,
        action_expected_value_delta_yen:,
        final_expected_value_yen:,
        recovery_success_probability:,
        repair_cost_yen:,
        human_cost_yen:,
        impact_days:,
        unresolved_run_count: runs.size,
        impacted_business_count:,
        calculation_method: missing_inputs.empty? ? "recent_30d_actual_average" : "fallback_#{missing_inputs.join('+')}",
        estimate_confidence: missing_inputs.empty? ? "high" : (missing_inputs.size <= 1 ? "medium" : "low"),
        missing_inputs:,
        daily_improvement_value_yen:,
        daily_new_business_value_yen:,
        daily_learning_loss_yen:,
        recurrence_expected_loss_yen:
      )
    end

    def candidate_today_expected_value_yen(candidate)
      return candidate.expected_profit_yen.to_i unless candidate.business

      result = business_expected_value_for(candidate.business)
      row = result.opportunities.find { |opportunity| opportunity.candidate_ids.include?(candidate.id) }
      return candidate.expected_profit_yen.to_i unless row

      [ (row.final_value_yen.to_d / row.candidate_ids.size).round, 0 ].max
    end

    def business_expected_value_for(business)
      @business_expected_value_for ||= {}
      @business_expected_value_for[business.id] ||= Aicoo::BusinessExpectedValue.call(business)
    end

    def persist_daily_run_valuation!(step, valuation)
      return unless step

      metadata = step.metadata.to_h
      valuation_payload = {
        "avoided_loss_yen" => valuation.avoided_loss_yen,
        "expected_value_if_no_action_yen" => valuation.expected_value_if_no_action_yen,
        "expected_value_if_action_yen" => valuation.expected_value_if_action_yen,
        "execution_cost_yen" => valuation.repair_cost_yen,
        "action_expected_value_delta_yen" => valuation.action_expected_value_delta_yen,
        "valuation_period_days" => valuation.impact_days,
        "valuation_status" => valuation.action_expected_value_delta_yen.positive? ? "positive" : "negative",
        "final_expected_value_yen" => valuation.final_expected_value_yen,
        "recovery_success_probability" => valuation.recovery_success_probability.to_f,
        "repair_cost_yen" => valuation.repair_cost_yen,
        "human_cost_yen" => valuation.human_cost_yen,
        "impact_days" => valuation.impact_days,
        "unresolved_run_count" => valuation.unresolved_run_count,
        "impacted_business_count" => valuation.impacted_business_count,
        "calculation_method" => valuation.calculation_method,
        "estimate_confidence" => valuation.estimate_confidence,
        "missing_inputs" => valuation.missing_inputs,
        "daily_improvement_value_yen" => valuation.daily_improvement_value_yen,
        "daily_new_business_value_yen" => valuation.daily_new_business_value_yen,
        "daily_learning_loss_yen" => valuation.daily_learning_loss_yen,
        "recurrence_expected_loss_yen" => valuation.recurrence_expected_loss_yen,
        "calculated_at" => Time.current.iso8601
      }
      return if metadata["today_valuation"].to_h.except("calculated_at") == valuation_payload.except("calculated_at")

      step.update_columns(
        metadata: metadata.merge("today_valuation" => valuation_payload),
        updated_at: Time.current
      )
    end

    def active_impacted_business_count
      count = Business.real_businesses.where(resource_status: %w[active watch]).count
      count.positive? ? count : 1
    end

    def recent_daily_candidate_value_yen
      scope = ActionCandidate.active_for_ranking.where(created_at: 30.days.ago..Time.current)
      return 0 unless scope.exists?

      (scope.sum(:expected_profit_yen).to_d / recent_day_denominator(scope.minimum(:created_at))).round
    end

    def recent_daily_new_business_value_yen
      scope = ActionCandidate
        .active_for_ranking
        .where(generation_source: "serp", department: "new_business")
        .where(created_at: 30.days.ago..Time.current)
      return 0 unless scope.exists?

      (scope.sum(:expected_profit_yen).to_d / recent_day_denominator(scope.minimum(:created_at))).round
    end

    def recent_daily_learning_value_yen
      scope = ActionCandidate.active_for_ranking.where(created_at: 30.days.ago..Time.current)
      return 0 unless scope.exists?

      (scope.sum(:expected_learning_value_yen).to_d / recent_day_denominator(scope.minimum(:created_at))).round
    end

    def step_adjusted_daily_improvement_value_yen(step_name)
      base = recent_daily_candidate_value_yen.to_d
      case step_name
      when "business_metrics_import"
        [ (base * 0.1).round, active_impacted_business_count * 1_000 ].min
      when "insight_generation"
        [ (base * 0.15).round, active_impacted_business_count * 1_500 ].min
      else
        [ (base * 0.2).round, active_impacted_business_count * 2_000 ].min
      end
    end

    def step_adjusted_daily_new_business_value_yen(step_name)
      base = recent_daily_new_business_value_yen.to_d
      case step_name
      when "insight_generation"
        [ (base * 0.25).round, active_impacted_business_count * 1_000 ].min
      when "business_metrics_import"
        0
      else
        [ (base * 0.1).round, active_impacted_business_count * 500 ].min
      end
    end

    def step_adjusted_daily_learning_value_yen(step_name)
      base = recent_daily_learning_value_yen.to_d
      case step_name
      when "business_metrics_import", "insight_generation"
        [ (base * 0.15).round, active_impacted_business_count * 500 ].min
      else
        [ (base * 0.2).round, active_impacted_business_count * 750 ].min
      end
    end

    def recent_day_denominator(oldest_created_at)
      return 30 if oldest_created_at.blank?

      [ (Date.current - oldest_created_at.to_date).to_i + 1, 1 ].max
    end

    def estimated_daily_run_human_cost_yen(runs)
      base_hours = 1.to_d
      duplicate_review_hours = [ runs.size - 1, 0 ].max * 0.05.to_d
      ((base_hours + duplicate_review_hours) * DAILY_RUN_OWNER_HOURLY_COST_YEN).round
    end

    def daily_run_recovery_success_probability(latest, runs)
      probability = latest.status == "partial_failed" ? 0.9.to_d : 0.8.to_d
      probability -= 0.05.to_d if runs.size >= 3
      [ probability, 0.6.to_d ].max
    end

    def daily_run_dedupe_key(run)
      step = daily_run_last_step(run)
      [
        "daily_run",
        step&.step_name.presence || "unknown_step",
        normalized_reason(daily_run_reason(run, step))
      ].join(":")
    end

    def daily_run_issue_recovered?(runs)
      latest = runs.max_by { |run| [ run.started_at || run.created_at, run.id ] }
      step_name = daily_run_last_step(latest)&.step_name
      return false if step_name.blank?

      latest_step_run = AicooDailyRun
        .actual_runs
        .joins(:aicoo_daily_run_steps)
        .where(aicoo_daily_run_steps: { step_name: })
        .order(Arel.sql("COALESCE(aicoo_daily_runs.started_at, aicoo_daily_runs.created_at) DESC"), Arel.sql("aicoo_daily_runs.id DESC"))
        .first
      return true if latest_step_run&.succeeded?

      recent_step_runs = AicooDailyRun
        .actual_runs
        .joins(:aicoo_daily_run_steps)
        .where(aicoo_daily_run_steps: { step_name: })
        .order(Arel.sql("COALESCE(aicoo_daily_runs.started_at, aicoo_daily_runs.created_at) DESC"), Arel.sql("aicoo_daily_runs.id DESC"))
        .limit(2)
      recent_step_runs.size >= 2 && recent_step_runs.all?(&:succeeded?)
    end

    def daily_run_last_step(run)
      steps = run.aicoo_daily_run_steps.to_a
      steps.select { |step| step.status == "running" }
           .max_by { |step| [ step.started_at || Time.zone.at(0), step.created_at, step.id ] } ||
        steps.max_by { |step| [ step.started_at || step.finished_at || Time.zone.at(0), step.created_at, step.id ] }
    end

    def daily_run_reason(run, step)
      step&.error_message.presence ||
        step&.metadata.to_h["error"].presence ||
        step&.metadata.to_h["exception"].presence ||
        step&.metadata.to_h["message"].presence ||
        run.error_message.presence ||
        run.calibration_error.presence ||
        "Run Logを確認してください。"
    end

    def normalized_reason(reason)
      reason.to_s.squish.first(120).presence || "unknown"
    end

    def external_target_url_for_existing_business?(candidate)
      return false if Aicoo::DataSourcePolicy.for(candidate.business).exploration_business?
      metadata = candidate.metadata.to_h
      return true if metadata["url_classification"].to_s == "external_reference"
      return true if metadata["target_url_type"].to_s == "external_reference"

      possible_target_urls(candidate).any? do |target|
        next false unless target.to_s.match?(%r{\Ahttps?://}i)

        !BusinessOwnedUrlPolicy.call(business: candidate.business, url: target).owner_page?
      end
    end

    def detected_target_url_for(candidate)
      possible_target_urls(candidate).find do |target|
        target.to_s.match?(%r{\Ahttps?://}i) ||
          target.to_s.start_with?("/")
      end
    end

    def possible_target_urls(candidate)
      metadata = candidate.metadata.to_h
      [
        metadata["target_url"],
        metadata["target_url_or_identifier"],
        metadata["page_path"],
        metadata.dig("article_candidate", "url"),
        metadata.dig("article_candidate", "recommended_url"),
        metadata.dig("new_article", "url"),
        metadata.dig("new_article", "recommended_url"),
        metadata.dig("action_plan", "target"),
        metadata.dig("action_plan", "target_url_or_identifier"),
        metadata.dig("action_plan", "page_path"),
        metadata.dig("decision", "selected", "target_url_or_identifier"),
        metadata.dig("action_expansion", "target_url"),
        metadata.dig("evidence", "page_path")
      ].flatten.compact_blank.map(&:to_s)
    end

    def invalid_target_path_reason(candidate)
      metadata = candidate.metadata.to_h
      return "target_type_mismatch" if existing_page_improvement?(candidate) && metadata["page_exists"] == false

      path = possible_target_urls(candidate).find { |target| target.start_with?("/") }
      return "invalid_target_path" if metadata["url_classification"].to_s == "invalid" || metadata["target_url_type"].to_s == "invalid"
      return unless path

      return "invalid_target_path" if path.include?("/-")

      article_match = path.match(ARTICLE_PATH_PATTERN)
      return unless article_match

      slug = article_match[1].to_s
      return "missing_slug" if slug.blank? || slug == "-" || slug.start_with?("-")
      return "invalid_target_path" unless slug.match?(/\A[a-z0-9][a-z0-9\-]*\z/i)
      return "target_type_mismatch" if existing_page_improvement?(candidate) && metadata["page_exists"] == false

      nil
    end

    def proposed_new_target?(candidate)
      metadata = candidate.metadata.to_h
      return true if metadata["url_classification"].to_s == "proposed_new"
      return true if metadata["target_url_type"].to_s == "proposed_new"

      possible_target_urls(candidate).any? do |target|
        next false unless target.to_s.start_with?("/")

        Aicoo::BusinessOwnedUrlPolicy.call(business: candidate.business, url: target).proposed_new?
      end
    end

    def new_business_today_actionable?(business)
      metadata = business.metadata.to_h
      return true if metadata["today_actionable"] == true
      return true if metadata["owner_next_step"].present? || metadata["next_action"].present?
      return true if metadata["validation_plan"].present?
      return true if parse_date(metadata["due_on"]) == Date.current
      return true if business.next_review_on.present? && business.next_review_on <= Date.current

      false
    end

    def new_business_score(business)
      business_value = Aicoo::BusinessExpectedValue.call(business)
      valuation = new_business_valuation(business, business_value)
      expected_value = valuation.fetch(:action_expected_value_delta_yen)
      metadata = business.metadata.to_h
      learning_value = numeric_metadata(metadata, "learning_value")

      expected_value.to_d + learning_value
    end

    def new_business_valuation(business, business_value)
      metadata = business.metadata.to_h
      new_business_value = business_value.new_business_value
      estimated_90d_profit_yen = first_present_integer(
        metadata["estimated_90d_profit_yen"],
        metadata["expected_90d_profit_yen"],
        new_business_value&.estimated_90d_profit_yen
      ) || 0
      success_probability = decimal_value(
        metadata["validation_success_probability"].presence || metadata["success_probability"].presence || new_business_value&.validation_success_probability,
        fallback: 0.15
      )
      failure_residual_value_yen = first_present_integer(metadata["failure_residual_value_yen"], metadata["residual_value_yen"]) || 0
      validation_cost_yen = first_present_integer(
        metadata["validation_cost_yen"],
        metadata["initial_cost_yen"],
        new_business_value&.validation_cost_yen
      ) || 0
      inaction_loss_yen = first_present_integer(metadata["inaction_loss_yen"], metadata["opportunity_decay_loss_yen"]) || 0
      expected_value_if_no_action_yen = first_present_integer(metadata["expected_value_if_no_action_yen"]) || -inaction_loss_yen
      expected_value_if_action_yen = ((estimated_90d_profit_yen.to_d * success_probability) + (failure_residual_value_yen.to_d * (1 - success_probability))).round
      delta_yen = expected_value_if_action_yen - expected_value_if_no_action_yen - validation_cost_yen

      {
        expected_value_if_no_action_yen:,
        expected_value_if_action_yen:,
        execution_cost_yen: validation_cost_yen,
        action_expected_value_delta_yen: delta_yen,
        valuation_period_days: 90,
        calculation_method: "new_business_counterfactual_delta",
        confidence: success_probability,
        valuation_status: valuation_status_for(delta_yen)
      }
    end

    def new_business_group_key(business)
      metadata = business.metadata.to_h
      raw = metadata["discovery_fingerprint"].presence ||
        metadata["source_query"].presence ||
        metadata.dig("serp", "query").presence ||
        metadata["market"].presence ||
        metadata["problem"].presence ||
        business.name

      normalized_new_business_text(raw)
    end

    def new_business_group_label(business)
      metadata = business.metadata.to_h
      raw = metadata["market"].presence ||
        metadata["source_query"].presence ||
        business.name

      raw.to_s.gsub(/の?検証事業/, "").presence || business.name
    end

    def normalized_new_business_text(value)
      value.to_s.downcase
        .unicode_normalize(:nfkc)
        .gsub(/https?:\/\/\S+/, "")
        .gsub(/(比較|おすすめ|料金|利用者を集める|検証事業|の検証|サービス|とは|向け|候補|新規事業)/, "")
        .gsub(/[[:space:]　\-_｜|・:：\/]+/, "")
        .presence || "unknown"
    end

    def parse_date(value)
      return value.to_date if value.respond_to?(:to_date)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def existing_page_improvement?(candidate)
      candidate.action_type.in?(%w[seo_improvement article_update]) ||
        candidate.metadata.to_h["work_type"].to_s == "existing_page_improvement" ||
        candidate.metadata.to_h["target_url_type"].to_s.in?(%w[owner_page own_existing])
    end

    def unrealistic_expected_profit?(candidate)
      expected_value = candidate.expected_profit_yen.to_i
      return false if expected_value <= HIGH_VALUE_REVIEW_THRESHOLD_YEN

      value_model = candidate.metadata.to_h["value_model"].to_h
      return true if value_model.blank?
      return true if value_model["valuation_review_required"] == true
      return true if value_model["valuation_state"].to_s == "valuation_review_required"
      return true if value_model["evidence_level"].to_s == "low"
      return true if decimal_value(value_model["confidence"], fallback: candidate.success_probability).to_d < 0.5.to_d
      return true if decimal_value(value_model["outlier_ratio"], fallback: 1).to_d >= 50.to_d
      return true if candidate.action_type.in?(%w[seo_improvement article_update]) && value_model["evidence_level"].to_s != "high"

      false
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

    def first_present_integer(*values)
      values.find { |value| !value.nil? && value.to_s.present? }&.to_i
    end

    def confidence_value_for(candidate)
      metadata = candidate.metadata.to_h
      value = metadata.dig("action_value_model", "confidence").presence ||
        metadata.dig("value_model", "confidence").presence ||
        candidate.success_probability
      decimal_value(value, fallback: 0.5).clamp(0.to_d, 1.to_d)
    end

    def valuation_status_for(delta_yen)
      return "positive" if delta_yen.positive?
      return "negative" if delta_yen.negative?

      "neutral"
    end

    def decimal_value(value, fallback:)
      value.to_d
    rescue ArgumentError, NoMethodError
      fallback.to_d
    end
  end
end

module Aicoo
  class TodayActionBoard
    include Rails.application.routes.url_helpers

    DESCRIPTION = "Todayは、自動改修が止まって承認が必要なもの、またはCodexでは実行できない手作業・記事作成・データ入力を、期待値順に処理する画面です。".freeze
    MODES = %w[revenue learning balanced].freeze
    APPROVAL_REQUIRED_STATUSES = %w[draft waiting_approval approved].freeze
    CODEX_QUEUE_STATUSES = %w[queued ready_for_codex sent_to_codex running].freeze
    OWNER_EXECUTION_MODES = %w[manual_operation content_creation data_operation owner_decision].freeze
    MAX_TOTAL_ITEMS = 15
    MAX_DAILY_RUN_ISSUES = 3
    MAX_APPROVAL_ITEMS = 3
    MAX_IMPROVEMENT_ITEMS = 5
    MAX_NEW_BUSINESS_ITEMS = 3
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

    Board = Data.define(:mode, :tabs, :items, :description)
    Tab = Data.define(:key, :label, :path, :active)
    DailyRunValuation = Data.define(
      :avoided_loss_yen,
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
      :group_count,
      :group_summary,
      :revenue_score,
      :learning_score,
      :balanced_score,
      :score
    )

    def initialize(mode: nil, limit: MAX_TOTAL_ITEMS)
      @mode = MODES.include?(mode.to_s) ? mode.to_s : "revenue"
      limit_value = limit.respond_to?(:to_i) ? limit.to_i : MAX_TOTAL_ITEMS
      @limit = [ limit_value.positive? ? limit_value : MAX_TOTAL_ITEMS, MAX_TOTAL_ITEMS ].min
    end

    def call
      items = candidate_items
      ranked_items = select_today_items(items)
        .sort_by { |item| today_sort_key(item) }
        .first(limit)
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
      daily_run_issue_items +
        action_candidate_items +
        new_business_items
    end

    def select_today_items(items)
      sorted = items.sort_by { |item| today_sort_key(item) }
      daily_run_items = sorted.select { |item| item.source_type == "daily_run_issue" }.first(MAX_DAILY_RUN_ISSUES)
      approval_items = sorted.select { |item| item.approval_required }.first(MAX_APPROVAL_ITEMS)
      improvement_items = sorted.select { |item| item.source_type.in?(%w[action_candidate auto_revision_task]) && !item.approval_required }.first(MAX_IMPROVEMENT_ITEMS)
      new_business_items = sorted.select { |item| item.source_type == "new_business" }.first(MAX_NEW_BUSINESS_ITEMS)

      (daily_run_items + approval_items + improvement_items + new_business_items).uniq(&:stable_id).first(limit)
    end

    def action_candidate_items
      ActionCandidate
        .active_for_ranking
        .includes(:business, :auto_revision_tasks)
        .order(updated_at: :desc)
        .limit(1_000)
        .filter_map { |candidate| build_item(candidate) }
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
        stable_id: "action_candidate:#{candidate.id}",
        rank: nil,
        source_type: approval_task ? "auto_revision_task" : "action_candidate",
        record: approval_task || candidate,
        priority: approval_task ? "critical" : "improvement",
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
        group_count: 1,
        group_summary: nil,
        revenue_score: revenue_score.round(2),
        learning_score: learning_score.round(2),
        balanced_score: balanced_score.round(2),
        score: selected_score.round(2)
      )
    end

    def daily_run_issue_items
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
          .map { |grouped_runs| build_daily_run_issue_item(grouped_runs) }
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
        expected_value_yen: valuation.final_expected_value_yen,
        expected_hours: 1.0,
        expected_hourly_value_yen: valuation.final_expected_value_yen,
        success_probability: valuation.recovery_success_probability,
        execution_mode: "system_recovery",
        execution_mode_label: "障害対応",
        data_sources_label: "Daily Run",
        approval_required: false,
        codex_target: false,
        owner_next_step: "#{step_name}を修復する",
        detail_url: aicoo_daily_run_path(latest, anchor: "step-breakdown"),
        reason: "#{reason} / 損失回避額 #{valuation.avoided_loss_yen.to_fs(:delimited)}円 / 復旧成功率 #{(valuation.recovery_success_probability * 100).round}% / 修正コスト #{valuation.repair_cost_yen.to_fs(:delimited)}円",
        stopped_reason: "影響日数 #{valuation.impact_days}日 / 影響Business #{valuation.impacted_business_count}件 / 同一障害 #{count}件 / 算定方法 #{valuation.calculation_method} / 信頼度 #{valuation.estimate_confidence} / 最新Run ##{latest.id} / 最古Run ##{oldest.id}",
        group_count: count,
        group_summary: "影響日数 #{valuation.impact_days}日 / 同一障害 #{count}件 / 損失回避額 #{valuation.avoided_loss_yen.to_fs(:delimited)}円",
        revenue_score: valuation.final_expected_value_yen,
        learning_score: valuation.daily_learning_loss_yen,
        balanced_score: ((valuation.final_expected_value_yen.to_d * 0.6) + (valuation.daily_learning_loss_yen.to_d * 0.4)).round(2),
        score: score_for(
          revenue_score: valuation.final_expected_value_yen.to_d,
          learning_score: valuation.daily_learning_loss_yen.to_d,
          balanced_score: (valuation.final_expected_value_yen.to_d * 0.6) + (valuation.daily_learning_loss_yen.to_d * 0.4)
        ).round(2)
      )
    end

    def new_business_items
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

    def build_new_business_item(group)
      business = group.max_by { |item| new_business_score(item) }
      expected_value_yen = business.metadata.to_h["expected_value_yen"].to_i
      expected_hours = positive_decimal(business.metadata.to_h["expected_hours"].presence || 2)
      success_probability = decimal_value(business.metadata.to_h["success_probability"], fallback: 0.3)
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
        expected_hours: expected_hours.to_f,
        expected_hourly_value_yen: expected_hours.positive? ? (expected_value_yen.to_d / expected_hours).round.to_i : 0,
        success_probability:,
        execution_mode: "owner_decision",
        execution_mode_label: "新規事業検証",
        data_sources_label: "SERP / 新規事業",
        approval_required: false,
        codex_target: false,
        owner_next_step: business.metadata.to_h["owner_next_step"].presence || business.metadata.to_h["next_action"].presence || "代表案を確認し、残りを統合またはアーカイブする",
        detail_url: owner_new_business_pipeline_path(selected: "business:#{business.id}"),
        reason: business.metadata.to_h["reason"].presence || "探索中の新規事業です。",
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
      return "inactive_business" if candidate.business.blank? || candidate.business.resource_status == "archived"
      return "no_score" unless minimum_fields_present?(candidate, execution_mode)
      return "zero_expected_value" if candidate.expected_profit_yen.to_i <= 0 && approval_task.blank?
      return "fallback_action" if candidate.metadata.to_h["today_fallback"]
      return "needs_refinement" if candidate.metadata.to_h["concretization_status"] == "needs_refinement"
      return "abstract_concrete_task" unless concrete_text_allowed?(candidate)
      return "external_data_source_disallowed" if external_data_source_used_for_existing_business?(candidate)
      return "external_target_url" if external_target_url_for_existing_business?(candidate)
      return invalid_target_path_reason(candidate) if invalid_target_path_reason(candidate).present?
      return "unrealistic_expected_profit" if unrealistic_expected_profit?(candidate)

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

    def mark_today_included!(candidate)
      metadata = candidate.metadata.to_h
      return if metadata["today_exclusion_reason"].blank? && metadata["today_included_at"].present?

      candidate.update_columns(
        metadata: metadata.except("today_exclusion_reason", "today_excluded_at", "detected_target_url").merge(
          "today_included_at" => Time.current.iso8601,
          "today_mode" => mode
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

    def priority_rank(item)
      case item.priority
      when "critical" then 0
      when "high" then 1
      when "improvement" then 3
      when "new_business" then 4
      else 5
      end
    end

    def today_sort_key(item)
      [
        -item.expected_value_yen.to_i,
        -item.score.to_d,
        priority_rank(item),
        item.business_name.to_s,
        item.stable_id.to_s
      ]
    end

    def daily_run_issue_valuation(runs, latest:)
      impact_days = [ runs.map(&:target_date).compact.uniq.size, 1 ].max
      impacted_business_count = active_impacted_business_count
      missing_inputs = []

      daily_improvement_value_yen = recent_daily_candidate_value_yen
      unless daily_improvement_value_yen.positive?
        missing_inputs << "recent_action_candidate_value"
        daily_improvement_value_yen = impacted_business_count * DAILY_RUN_STANDARD_LOSS_PER_BUSINESS_YEN
      end

      daily_new_business_value_yen = recent_daily_new_business_value_yen
      unless daily_new_business_value_yen.positive?
        missing_inputs << "recent_new_business_value"
        daily_new_business_value_yen = impacted_business_count * DAILY_RUN_STANDARD_NEW_BUSINESS_LOSS_PER_BUSINESS_YEN
      end

      daily_learning_loss_yen = recent_daily_learning_value_yen
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
      final_expected_value_yen = ((avoided_loss_yen.to_d * recovery_success_probability) - repair_cost_yen).round
      final_expected_value_yen = [ final_expected_value_yen, DAILY_RUN_MINIMUM_AVOIDED_LOSS_YEN / 2 ].max

      DailyRunValuation.new(
        avoided_loss_yen:,
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

    def persist_daily_run_valuation!(step, valuation)
      return unless step

      metadata = step.metadata.to_h
      valuation_payload = {
        "avoided_loss_yen" => valuation.avoided_loss_yen,
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

    def new_business_today_actionable?(business)
      metadata = business.metadata.to_h
      return true if metadata["today_actionable"] == true
      return true if metadata["owner_next_step"].present? || metadata["next_action"].present?
      return true if metadata["validation_plan"].present? && new_business_score(business).positive?
      return true if parse_date(metadata["due_on"]) == Date.current
      return true if business.next_review_on.present? && business.next_review_on <= Date.current

      false
    end

    def new_business_score(business)
      metadata = business.metadata.to_h
      expected_value = metadata["expected_value_yen"].to_i
      success_probability = decimal_value(metadata["success_probability"], fallback: 0.3)
      learning_value = numeric_metadata(metadata, "learning_value")

      (expected_value.to_d * success_probability) + learning_value
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
        candidate.metadata.to_h["target_url_type"].to_s == "owner_page"
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

    def decimal_value(value, fallback:)
      value.to_d
    rescue ArgumentError, NoMethodError
      fallback.to_d
    end
  end
end

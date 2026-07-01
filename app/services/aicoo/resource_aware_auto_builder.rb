module Aicoo
  class ResourceAwareAutoBuilder
    Result = Data.define(:created_tasks, :skipped, :budget) do
      def created_count
        created_tasks.size
      end

      def skipped_count
        skipped.size
      end

      def diagnostics
        {
          "created_count" => created_count,
          "skipped_count" => skipped_count,
          "skipped_reasons" => skipped.first(20)
        }
      end
    end

    Decision = Data.define(
      :business,
      :landing_page,
      :lp_summary,
      :strategy,
      :expected_value_yen,
      :learning_value_score,
      :estimated_cost_yen,
      :estimated_build_hours,
      :priority_score,
      :reason
    )

    BUILDABLE_LIFECYCLE_STAGES = %w[idea lp_validation].freeze
    ACTIVE_TASK_STATUSES = %w[pending building].freeze

    def initialize(today: Date.current, budget: AicooResourceBudget.current)
      @today = today.to_date
      @budget = budget
    end

    def call(daily_run: nil, limit: nil)
      return disabled_result if budget.auto_build_enabled? == false

      created = []
      skipped = []
      decisions.first(limit || budget.build_queue_limit).each do |decision|
        if AutoBuildTask.where(business: decision.business, status: ACTIVE_TASK_STATUSES).exists?
          skipped << "#{decision.business.name}: active_auto_build_task_exists"
          next
        end

        unless buildable_with_resources?(decision)
          skipped << "#{decision.business.name}: resource_not_available"
          next
        end

        created << create_task!(decision, daily_run:)
      end

      Result.new(created_tasks: created, skipped:, budget:)
    end

    def decisions
      @decisions ||= candidate_businesses.filter_map { |business| decision_for(business) }
                                       .sort_by { |decision| [ -decision.priority_score.to_d, decision.business.name ] }
    end

    def learning_value_for_business(business)
      learning_value_for(business)
    end

    private

    attr_reader :today, :budget

    def disabled_result
      Result.new(
        created_tasks: [],
        skipped: [ "AicooResourceBudget.auto_build_enabled=false" ],
        budget:
      )
    end

    def candidate_businesses
      Business.real_businesses
              .where(lifecycle_stage: BUILDABLE_LIFECYCLE_STAGES)
              .where(auto_build_enabled: true)
              .includes(:aicoo_lab_landing_pages, :business_metric_dailies, :business_activity_logs, :business_execution_profile)
    end

    def decision_for(business)
      landing_page, lp_summary = best_landing_page_for(business)
      return unless landing_page && lp_summary

      learning_value_score = learning_value_for(business)
      expected_value_yen = expected_value_for(lp_summary)
      strategy = strategy_for(expected_value_yen:, lp_summary:, learning_value_score:)
      return unless strategy

      estimated_cost_yen = estimated_cost_for(business, strategy)
      estimated_build_hours = estimated_hours_for(strategy)
      reason = reason_for(lp_summary:, strategy:, learning_value_score:, expected_value_yen:)
      priority_score = priority_score_for(expected_value_yen:, learning_value_score:, estimated_cost_yen:, estimated_build_hours:)

      Decision.new(
        business:,
        landing_page:,
        lp_summary:,
        strategy:,
        expected_value_yen:,
        learning_value_score:,
        estimated_cost_yen:,
        estimated_build_hours:,
        priority_score:,
        reason:
      )
    end

    def best_landing_page_for(business)
      summaries = Aicoo::LpEvaluationSummary.for_business(business)
      summary = summaries.max_by { |row| [ verdict_rank(row.verdict), row.cv, row.cta_clicks, row.pv ] }
      [ summary&.landing_page, summary ]
    end

    def strategy_for(expected_value_yen:, lp_summary:, learning_value_score:)
      return "priority_a" if expected_value_yen >= 30_000 || lp_summary.verdict == "strong"
      return "priority_b" if expected_value_yen >= 10_000 || lp_summary.verdict == "promising"
      return "priority_c" if learning_value_score >= 70

      nil
    end

    def buildable_with_resources?(decision)
      return true if decision.strategy == "priority_a" && budget.budget_available?(decision.estimated_cost_yen)

      budget.resource_available_for?(decision.estimated_cost_yen)
    end

    def create_task!(decision, daily_run:)
      AutoBuildTask.transaction do
        action_candidate = create_action_candidate!(decision)
        auto_revision_task = create_auto_revision_task!(action_candidate, decision)
        AutoBuildTask.create!(
          business: decision.business,
          aicoo_daily_run: daily_run,
          auto_revision_task:,
          status: "pending",
          build_strategy: decision.strategy,
          risk_level: decision.business.auto_build_risk_level,
          priority_score: decision.priority_score,
          expected_value_yen: decision.expected_value_yen,
          learning_value_score: decision.learning_value_score,
          estimated_cost_yen: decision.estimated_cost_yen,
          estimated_build_hours: decision.estimated_build_hours,
          reason: decision.reason,
          codex_prompt: auto_revision_task.codex_prompt,
          metadata: metadata_for(decision)
        )
      end
    end

    def create_action_candidate!(decision)
      decision.business.action_candidates.create!(
        title: "#{decision.business.name}のMVPを自動生成する",
        description: "LP検証とLearning Value、AICOOのリソース余裕を見てMVP生成候補にしました。",
        action_type: "build_mvp",
        department: "new_business",
        generation_source: "ai_business",
        status: "idea",
        immediate_value_yen: decision.expected_value_yen.to_i,
        expected_profit_yen: decision.expected_value_yen.to_i,
        expected_revenue_value_yen: decision.expected_value_yen.to_i,
        expected_learning_value_yen: (decision.learning_value_score.to_d * 1_000).to_i,
        final_expected_value_yen: (decision.expected_value_yen.to_d + decision.learning_value_score.to_d * 1_000).to_i,
        success_probability: success_probability_for(decision),
        expected_hours: decision.estimated_build_hours,
        cost_yen: decision.estimated_cost_yen.to_i,
        strategic_value_score: decision.learning_value_score.to_i,
        risk_reduction_score: 20,
        confidence_score: confidence_for(decision),
        data_confidence_score: confidence_for(decision),
        evaluation_reason: decision.reason,
        execution_prompt: build_prompt(decision),
        metadata: metadata_for(decision)
      )
    end

    def create_auto_revision_task!(action_candidate, decision)
      task = AutoRevisionTask.from_action_candidate(action_candidate, generated_by: "resource_aware_auto_builder")
      task.update!(
        title: action_candidate.title,
        execution_prompt: build_prompt(decision),
        priority_score: decision.priority_score,
        risk_level: decision.business.auto_build_risk_level,
        status: decision.business.auto_build_requires_approval? ? "waiting_approval" : "ready_for_codex",
        metadata: task.metadata.to_h.merge(metadata_for(decision).merge(
          "auto_build" => true,
          "manual_approval_required" => decision.business.auto_build_requires_approval?
        ))
      )
      task
    end

    def build_prompt(decision)
      Aicoo::MvpDevelopmentPromptBuilder.new(
        business: decision.business,
        landing_page: decision.landing_page,
        lp_summary: decision.lp_summary
      ).call
    end

    def learning_value_for(business)
      score = 30
      score += 20 if business.category.blank? || similar_business_count(business).zero?
      score += 15 if business.business_playbook.blank? || business.business_playbook.sample_count.to_i < 3
      score += 15 if business.action_results.count < 3
      score += 10 if business.revenue_events.revenue.count.zero?
      score += 10 if business.aicoo_lab_landing_pages.count <= 1
      [ score, 100 ].min
    end

    def similar_business_count(business)
      Business.real_businesses
              .where.not(id: business.id)
              .where(category: business.category)
              .where.not(category: [ nil, "" ])
              .count
    end

    def expected_value_for(lp_summary)
      base = lp_summary.cv.to_i * 20_000
      base += lp_summary.cta_clicks.to_i * 2_000
      base += [ lp_summary.pv.to_i * 100, 20_000 ].min
      base += 20_000 if lp_summary.verdict == "strong"
      base += 8_000 if lp_summary.verdict == "promising"
      base
    end

    def estimated_cost_for(business, strategy)
      base = { "priority_a" => 2_000, "priority_b" => 1_200, "priority_c" => 800 }.fetch(strategy)
      return base if business.aicoo_internal_codex?

      base + 1_000
    end

    def estimated_hours_for(strategy)
      { "priority_a" => 6, "priority_b" => 4, "priority_c" => 3 }.fetch(strategy).to_d
    end

    def priority_score_for(expected_value_yen:, learning_value_score:, estimated_cost_yen:, estimated_build_hours:)
      expected_value_yen.to_d + learning_value_score.to_d * 1_000 - estimated_cost_yen.to_d - estimated_build_hours.to_d * 500
    end

    def success_probability_for(decision)
      case decision.strategy
      when "priority_a" then 0.45
      when "priority_b" then 0.34
      else 0.22
      end
    end

    def confidence_for(decision)
      return 60 if decision.strategy == "priority_a"
      return 45 if decision.strategy == "priority_b"

      30
    end

    def reason_for(lp_summary:, strategy:, learning_value_score:, expected_value_yen:)
      [
        "Resource-Aware Auto Builder",
        "strategy=#{strategy}",
        "lp_verdict=#{lp_summary.verdict}",
        "pv=#{lp_summary.pv}",
        "cta=#{lp_summary.cta_clicks}",
        "cv=#{lp_summary.cv}",
        "expected_value_yen=#{expected_value_yen}",
        "learning_value_score=#{learning_value_score}"
      ].join(" / ")
    end

    def metadata_for(decision)
      {
        "resource_aware_auto_builder" => true,
        "build_strategy" => decision.strategy,
        "landing_page_id" => decision.landing_page.id,
        "landing_page_slug" => decision.landing_page.published_slug,
        "lp_verdict" => decision.lp_summary.verdict,
        "lp_pv" => decision.lp_summary.pv,
        "lp_cta_clicks" => decision.lp_summary.cta_clicks,
        "lp_cv" => decision.lp_summary.cv,
        "learning_value_score" => decision.learning_value_score.to_s,
        "estimated_cost_yen" => decision.estimated_cost_yen.to_s,
        "estimated_build_hours" => decision.estimated_build_hours.to_s,
        "auto_merge_enabled" => decision.business.business_execution_profile&.auto_merge_enabled? || false,
        "auto_deploy_enabled" => decision.business.business_execution_profile&.auto_deploy_enabled? || false
      }
    end

    def verdict_rank(verdict)
      Aicoo::LpEvaluationSummary.verdict_rank(verdict)
    end
  end
end

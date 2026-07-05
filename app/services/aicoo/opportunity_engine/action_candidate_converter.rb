module Aicoo
  module OpportunityEngine
    class ActionCandidateConverter
      def initialize(opportunity, analyzer:)
        @opportunity = opportunity
        @analyzer = analyzer
      end

      def call
        business = opportunity.business
        issue = opportunity.source_issue
        decision = Aicoo::UniversalImprovementStrategyEngine.call(opportunity)
        return unless decision.valid?

        plan = Aicoo::ActionPlanner.call(opportunity, analyzer:, decision:)
        return unless plan.valid?
        return unless concrete_action_valid?(plan)

        metadata = analyzer.candidate_metadata(issue, opportunity:).merge(
          "action_plan" => plan.to_metadata,
          "decision" => decision.to_metadata,
          "strategy_engine" => "Aicoo::UniversalImprovementStrategyEngine",
          "strategy_ranking" => decision.to_metadata["strategy_ranking"],
          "business_knowledge" => decision.business_knowledge.to_h,
          "concrete_task" => decision.concrete_task,
          "target" => decision.target,
          "target_type" => decision.target_type,
          "target_url_or_identifier" => decision.target_url_or_identifier,
          "execution_mode" => decision.execution_mode,
          "execution_units" => decision.execution_units,
          "codex_eligible" => decision.execution_mode == "code_revision"
        )

        candidate = business.action_candidates.create!(
          title: plan.summary,
          description: plan.goal,
          action_type: action_type,
          immediate_value_yen: decision.expected_profit_yen,
          success_probability: decision.success_probability,
          strategic_value_score: issue.strategic_value_score,
          risk_reduction_score: issue.risk_reduction_score,
          confidence_score: opportunity.confidence,
          data_confidence_score: opportunity.confidence,
          expected_hours: decision.expected_hours,
          cost_yen: decision.cost_yen,
          status: "idea",
          generation_source: "business_analyzer",
          metadata:,
          evaluation_reason: evaluation_reason_for(plan),
          execution_prompt: execution_prompt_for(plan)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload.update_columns(
          metadata: candidate.metadata.to_h.merge(
            "action_plan" => plan.to_metadata,
            "decision" => decision.to_metadata,
            "strategy_engine" => "Aicoo::UniversalImprovementStrategyEngine",
            "strategy_ranking" => decision.to_metadata["strategy_ranking"],
            "business_knowledge" => decision.business_knowledge.to_h,
            "opportunity" => opportunity.to_metadata,
            "evidence" => analyzer.evidence_for(issue),
            "execution_units" => plan.execution_units,
            "execution_mode" => plan.execution_mode,
            "concrete_task" => plan.summary,
            "codex_eligible" => plan.execution_mode == "code_revision"
          ),
          execution_prompt: execution_prompt_for(plan),
          updated_at: Time.current
        )
        candidate.reload
      end

      private

      attr_reader :opportunity, :analyzer

      def action_type
        value = opportunity.source_issue.action_type.to_s
        return value if ActionCandidate::ACTION_TYPES.include?(value)

        {
          "lp_improvement" => "ui_improvement",
          "asset_creation" => "build_lp",
          "operations" => "data_preparation"
        }.fetch(value, "other")
      end

      def evaluation_reason_for(plan)
        [
          "business_analyzer:#{opportunity.key}",
          "opportunity:#{opportunity.key}",
          "action_planner:#{opportunity.key}",
          plan.owner_output
        ].join("\n")
      end

      def execution_prompt_for(plan)
        return nil unless plan.execution_mode == "code_revision"

        <<~PROMPT.strip
          Action Planner 作業指示

          #{plan.owner_output}

          実行手順:
          #{plan.execution_steps.map.with_index(1) { |step, index| "#{index}. #{step}" }.join("\n")}

          完了条件:
          - 上記手順が完了している
          - 実行結果をActionResultへ登録できるメモがある
        PROMPT
      end

      ABSTRACT_PATTERNS = [
        /検索需要があるテーマ/,
        /CVを改善/,
        /CV改善\z/,
        /SEO改善\z/,
        /SEOを改善/,
        /UXを改善/,
        /CTAを改善/,
        /デザインを改善/,
        /サイト改善/,
        /導線改善/,
        /記事を増やす/,
        /Analyzer/i
      ].freeze

      def concrete_action_valid?(plan)
        text = plan.summary.to_s.strip
        return false if text.blank?
        return false if ABSTRACT_PATTERNS.any? { |pattern| text.match?(pattern) }
        return false if plan.target.to_s.blank? || plan.target.to_s.include?("未特定")
        return false if plan.execution_units.blank?

        true
      end
    end
  end
end

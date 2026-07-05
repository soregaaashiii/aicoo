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
        plan = Aicoo::ActionPlanner.call(opportunity, analyzer:)
        return unless plan.valid?

        candidate = business.action_candidates.create!(
          title: plan.summary,
          description: plan.goal,
          action_type: action_type,
          immediate_value_yen: opportunity.expected_value_yen,
          success_probability: opportunity.success_probability,
          strategic_value_score: issue.strategic_value_score,
          risk_reduction_score: issue.risk_reduction_score,
          confidence_score: opportunity.confidence,
          data_confidence_score: opportunity.confidence,
          expected_hours: opportunity.expected_hours,
          cost_yen: 0,
          status: "idea",
          generation_source: "business_analyzer",
          metadata: analyzer.candidate_metadata(issue, opportunity:).merge("action_plan" => plan.to_metadata),
          evaluation_reason: evaluation_reason_for(plan),
          execution_prompt: execution_prompt_for(plan)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload.update_columns(
          metadata: candidate.metadata.to_h.merge(
            "action_plan" => plan.to_metadata,
            "opportunity" => opportunity.to_metadata,
            "evidence" => analyzer.evidence_for(issue),
            "execution_units" => plan.execution_units,
            "execution_mode" => plan.execution_mode
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
    end
  end
end

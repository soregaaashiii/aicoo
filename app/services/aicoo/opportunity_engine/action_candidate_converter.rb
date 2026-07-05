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
        candidate = business.action_candidates.create!(
          title: issue.title,
          description: issue.description,
          action_type: issue.action_type,
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
          metadata: analyzer.candidate_metadata(issue, opportunity:),
          evaluation_reason: analyzer.evaluation_reason(issue, opportunity:),
          execution_prompt: analyzer.execution_prompt(issue, opportunity:)
        )
        Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
        candidate.reload.update_columns(
          metadata: candidate.metadata.to_h.merge(
            "opportunity" => opportunity.to_metadata,
            "evidence" => analyzer.evidence_for(issue),
            "execution_units" => analyzer.execution_units_for(issue),
            "execution_mode" => opportunity.execution_mode
          ),
          updated_at: Time.current
        )
        candidate.reload
      end

      private

      attr_reader :opportunity, :analyzer
    end
  end
end

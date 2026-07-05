module Aicoo
  module OpportunityEngine
    Opportunity = Data.define(
      :key,
      :business,
      :source_analyzer,
      :opportunity_type,
      :target,
      :reason,
      :expected_value_yen,
      :expected_hours,
      :success_probability,
      :confidence,
      :execution_mode,
      :required_resources,
      :supporting_metrics,
      :source_issue
    ) do
      def to_metadata
        {
          "key" => key,
          "business_id" => business&.id,
          "source_analyzer" => source_analyzer,
          "opportunity_type" => opportunity_type,
          "target" => target.to_h.deep_stringify_keys,
          "reason" => reason,
          "expected_value_yen" => expected_value_yen.to_i,
          "expected_hours" => expected_hours.to_d.to_s,
          "success_probability" => success_probability.to_d.to_s,
          "confidence" => confidence.to_i,
          "execution_mode" => execution_mode,
          "required_resources" => required_resources.to_h.deep_stringify_keys,
          "supporting_metrics" => supporting_metrics.to_h.deep_stringify_keys
        }
      end
    end
  end
end

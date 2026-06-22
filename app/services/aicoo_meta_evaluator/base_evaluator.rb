module AicooMetaEvaluator
  class BaseEvaluator
    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    private

    attr_reader :action_candidate

    delegate :business, to: :action_candidate

    def result(evaluator_type:, expected_value_yen:, confidence_score:, reason:, metadata: {})
      EvaluationResult.new(
        evaluator_type:,
        expected_value_yen: expected_value_yen.to_i,
        confidence_score: confidence_score.to_i.clamp(0, 100),
        reason:,
        metadata:
      )
    end

    def recent_metrics(days: 30)
      business.business_metric_dailies.where(recorded_on: (days - 1).days.ago.to_date..Date.current)
    end

    def capped_confidence(value, max_value)
      return 0 if max_value.to_d.zero?

      ((value.to_d / max_value.to_d) * 100).round.clamp(0, 100)
    end
  end
end

module AicooMetaEvaluator
  class LearningEvaluator < BaseEvaluator
    def call
      action_result_shortage = shortage(ActionResult.count, AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED)
      metric_shortage = shortage(BusinessMetricDaily.select(:recorded_on).distinct.count, AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED)
      expected_value = action_candidate.expected_learning_value_yen.to_i
      confidence = learning_confidence(action_result_shortage, metric_shortage, expected_value)

      result(
        evaluator_type: "learning",
        expected_value_yen: expected_value,
        confidence_score: confidence,
        reason: reason_for(action_result_shortage, metric_shortage, expected_value),
        metadata: { action_result_shortage:, business_metric_daily_shortage: metric_shortage }
      )
    end

    private

    def shortage(current, required)
      [ required.to_i - current.to_i, 0 ].max
    end

    def learning_confidence(action_result_shortage, metric_shortage, expected_value)
      return 0 if expected_value.zero?
      return 85 if action_result_shortage.positive? || metric_shortage.positive?

      45
    end

    def reason_for(action_result_shortage, metric_shortage, expected_value)
      return "学習価値がない行動です。" if expected_value.zero?
      return "ActionResultやBusinessMetricが不足しており、学習価値が高い行動です。" if action_result_shortage.positive? || metric_shortage.positive?

      "学習データは一定量あり、追加学習価値は中程度です。"
    end
  end
end

module AicooMetaEvaluator
  class JudgeEvaluator < BaseEvaluator
    def call
      records = business.action_results.evaluated.includes(:action_candidate)
      relevant = records.select { |record| relevant_record?(record) }
      confidence = capped_confidence(relevant.size, 100)
      average_actual = average(relevant.map(&:actual_profit_yen))
      hit_rate = hit_rate_for(relevant)
      expected_value = average_actual || action_candidate.expected_profit_yen.to_i

      result(
        evaluator_type: "judge",
        expected_value_yen: expected_value,
        confidence_score: confidence,
        reason: reason_for(relevant.size, hit_rate),
        metadata: { evaluated_count: relevant.size, hit_rate: hit_rate&.to_f }
      )
    end

    private

    def relevant_record?(record)
      candidate = record.action_candidate
      candidate.generation_source == action_candidate.generation_source ||
        candidate.action_type == action_candidate.action_type
    end

    def hit_rate_for(records)
      return nil if records.empty?

      hits = records.count { |record| record.prediction_error_rate.to_d <= 0.5 || sign_matches?(record) }
      hits.to_d / records.size
    end

    def sign_matches?(record)
      predicted = record.predicted_expected_profit_yen.to_i
      actual = record.actual_profit_yen.to_i
      return true if predicted.zero? && actual.zero?

      predicted.positive? == actual.positive?
    end

    def average(values)
      numeric = values.compact.map(&:to_d)
      return nil if numeric.empty?

      (numeric.sum / numeric.size).round
    end

    def reason_for(count, hit_rate)
      return "ActionResultが不足しているため、Judge評価の信頼度は低いです。" if count < 10

      "類似ActionResultが#{count}件あり、的中率#{(hit_rate.to_d * 100).round}%を確認しました。"
    end
  end
end

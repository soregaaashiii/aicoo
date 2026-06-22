module AicooMetaEvaluator
  EvaluationResult = Data.define(:evaluator_type, :expected_value_yen, :confidence_score, :reason, :metadata) do
    def weighted_value
      expected_value_yen.to_d * (confidence_score.to_d / 100)
    end

    def to_h
      {
        evaluator_type:,
        expected_value_yen: expected_value_yen.to_i,
        confidence_score: confidence_score.to_i,
        reason:,
        metadata: metadata.to_h
      }
    end
  end
end

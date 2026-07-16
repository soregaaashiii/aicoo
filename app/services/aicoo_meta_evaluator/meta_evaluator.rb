module AicooMetaEvaluator
  class MetaEvaluator
    Result = Data.define(:final_expected_value_yen, :final_confidence_score, :evaluator_breakdown)

    EVALUATORS = [
      GscEvaluator,
      Ga4Evaluator,
      JudgeEvaluator,
      RevenueEvaluator,
      LearningEvaluator
    ].freeze

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      return seo_article_result if Aicoo::SeoArticleExpectedValue.applies_to?(action_candidate)

      results = evaluator_results
      confidence_sum = results.sum { |result| result.confidence_score.to_d / 100 }
      final_expected_value =
        if confidence_sum.positive?
          results.sum(&:weighted_value) / confidence_sum
        else
          action_candidate.expected_total_value_yen.to_d
        end

      Result.new(
        final_expected_value_yen: final_expected_value.round,
        final_confidence_score: final_confidence_score(results),
        evaluator_breakdown: results.map(&:to_h)
      )
    end

    private

    attr_reader :action_candidate

    def seo_article_result
      value = Aicoo::SeoArticleExpectedValue.call(action_candidate).final_expected_value_yen
      Result.new(
        final_expected_value_yen: value,
        final_confidence_score: action_candidate.confidence_score.to_i,
        evaluator_breakdown: [
          {
            "name" => "seo_article_incremental_click_model",
            "weighted_value" => value,
            "confidence_score" => action_candidate.confidence_score.to_i,
            "excluded_value_sources" => %w[learning judge business_expected_value]
          }
        ]
      )
    end

    def evaluator_results
      EVALUATORS.map { |evaluator| evaluator.new(action_candidate).call }
    end

    def final_confidence_score(results)
      active_results = results.select { |result| result.confidence_score.positive? }
      return 0 if active_results.empty?

      numerator = active_results.sum { |result| result.confidence_score.to_d * result.confidence_score.to_d }
      denominator = active_results.sum { |result| result.confidence_score.to_d }
      (numerator / denominator).round.clamp(0, 100)
    end
  end
end

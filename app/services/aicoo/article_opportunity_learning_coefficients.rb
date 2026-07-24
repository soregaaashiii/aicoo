module Aicoo
  class ArticleOpportunityLearningCoefficients
    MIN_BUSINESS_SAMPLE_SIZE = 3
    MIN_GLOBAL_SAMPLE_SIZE = 3
    MODEL_NAME = Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME

    Result = Data.define(:coefficients, :sources, :sample_counts, :learning_values, :source)

    def self.call(candidate, improvement_type, context: nil)
      new(candidate, improvement_type, context:).call
    end

    def initialize(candidate, improvement_type, context: nil)
      @candidate = candidate
      @improvement_type = improvement_type.to_s
      @context = context
    end

    def call
      business = coefficient_stats(results_for_business)
      return result_for("business_learning", business) if active?(business, MIN_BUSINESS_SAMPLE_SIZE)

      improvement = coefficient_stats(results_for_improvement_type)
      return result_for("improvement_type_learning", improvement) if active?(improvement, MIN_GLOBAL_SAMPLE_SIZE)

      global = coefficient_stats(results_for_all_article_opportunities)
      return result_for("global_learning", global) if active?(global, MIN_GLOBAL_SAMPLE_SIZE)

      Result.new(
        coefficients: {},
        sources: {},
        sample_counts: {
          "business_learning" => business.fetch(:sample_count),
          "improvement_type_learning" => improvement.fetch(:sample_count),
          "global_learning" => global.fetch(:sample_count)
        },
        learning_values: {},
        source: nil
      )
    end

    private

    attr_reader :candidate, :improvement_type, :context

    def result_for(source, stats)
      coefficients = stats.fetch(:coefficients)
      Result.new(
        coefficients:,
        sources: coefficients.keys.index_with { source },
        sample_counts: stats.fetch(:sample_counts),
        learning_values: coefficients,
        source:
      )
    end

    def active?(stats, minimum)
      stats.fetch(:sample_count).to_i >= minimum && stats.fetch(:coefficients).present?
    end

    def results_for_business
      article_opportunity_results.select { |result| result.business_id == candidate.business_id && result_improvement_type(result) == improvement_type }
    end

    def results_for_improvement_type
      article_opportunity_results.select { |result| result_improvement_type(result) == improvement_type }
    end

    def results_for_all_article_opportunities
      article_opportunity_results
    end

    def article_opportunity_results
      @article_opportunity_results ||= begin
        results = if context
          context.article_opportunity_results
        else
          ActionResult.evaluated
                      .includes(:action_candidate, :revenue_events)
                      .where.not(action_candidate_id: nil)
                      .to_a
        end
        results.select { |result| article_opportunity_result?(result) }
      end
    end

    def article_opportunity_result?(result)
      metadata = result.action_candidate&.metadata.to_h
      metadata["value_model_name"].to_s == MODEL_NAME ||
        metadata.dig("expected_profit_model", "name").to_s == Aicoo::ArticleOpportunityExpectedProfit::MODEL_NAME ||
        metadata.dig("expected_profit_model", "value_model").to_s == "grounded_article_opportunity_profit"
    end

    def result_improvement_type(result)
      metadata = result.action_candidate&.metadata.to_h
      first_present(
        metadata["opportunity_type"],
        metadata["improvement_type"],
        metadata.dig("expected_profit_model", "improvement_type"),
        metadata.dig("execution_brief", "target", "improvement_type")
      ).to_s
    end

    def coefficient_stats(results)
      samples = results.map { |result| coefficient_sample(result) }
      coefficients = average_coefficients(samples)
      {
        sample_count: results.size,
        sample_counts: {
          "business_learning" => results.count { |result| result.business_id == candidate.business_id && result_improvement_type(result) == improvement_type },
          "improvement_type_learning" => results.count { |result| result_improvement_type(result) == improvement_type },
          "global_learning" => results.size
        },
        coefficients:
      }
    end

    def coefficient_sample(result)
      candidate_metadata = result.action_candidate.metadata.to_h
      model = candidate_metadata["expected_profit_model"].to_h
      metrics = model.presence || candidate_metadata
      gsc = first_present(model["used_gsc"], candidate_metadata.dig("evidence", "gsc"), {}).to_h
      ga4 = first_present(model["used_ga4"], candidate_metadata.dig("evidence", "ga4"), {}).to_h
      impressions = decimal(first_present(gsc["impressions"], metrics["gsc_impressions"]))
      pageviews = decimal(first_present(ga4["pageviews"], metrics["ga4_pageviews"]))
      click_delta = positive_decimal(result.actual_clicks_delta)
      shop_click_delta = positive_decimal(result.actual_phone_clicks_delta) +
        positive_decimal(result.actual_map_clicks_delta) +
        positive_decimal(result.actual_affiliate_clicks_delta)
      pageview_delta = positive_decimal(result.actual_pageviews_delta)
      revenue_event_count = result.revenue_events.size
      actual_profit = positive_decimal(result.actual_profit_yen)

      {
        "ctr_gain_rate" => rate(click_delta, impressions),
        "content_ctr_gain_rate" => rate(click_delta, impressions),
        "internal_link_pageview_lift_rate" => rate(pageview_delta, pageviews),
        "shop_visit_rate" => rate(shop_click_delta, pageviews.positive? ? pageviews : pageview_delta),
        "conversion_rate" => revenue_event_count.positive? && click_delta.positive? ? revenue_event_count.to_d / click_delta : nil,
        "profit_per_conversion_yen" => revenue_event_count.positive? ? actual_profit / revenue_event_count : nil,
        "click_value_yen" => click_delta.positive? ? actual_profit / click_delta : nil,
        "rank_impression_gain_rate" => rate(positive_decimal(result.actual_impressions_delta), impressions)
      }.compact
    end

    def average_coefficients(samples)
      keys = samples.flat_map(&:keys).uniq
      keys.each_with_object({}) do |key, hash|
        values = samples.filter_map { |sample| sample[key] }.select(&:positive?)
        hash[key] = average(values) if values.any?
      end
    end

    def average(values)
      values.sum.to_d / values.size
    end

    def rate(numerator, denominator)
      numerator = decimal(numerator)
      denominator = decimal(denominator)
      return nil unless numerator.positive? && denominator.positive?

      numerator / denominator
    end

    def positive_decimal(value)
      [ decimal(value), 0.to_d ].max
    end

    def decimal(value)
      return 0.to_d if value.nil?

      value.to_d
    rescue ArgumentError, NoMethodError
      0.to_d
    end

    def first_present(*values)
      values.find(&:present?)
    end
  end
end

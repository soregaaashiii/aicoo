module Aicoo
  class SuelogArticleExpectedValue
    CALCULATION_VERSION = "suelog_article_v1".freeze

    Result = Data.define(:expected_profit_yen, :metadata)

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(business:, query:, gsc_inputs:, ga4_inputs: {}, shopclick_inputs: {}, article_inputs: {}, success_probability: nil)
      @business = business
      @query = query.to_s.squish
      @gsc_inputs = gsc_inputs.to_h.deep_stringify_keys
      @ga4_inputs = ga4_inputs.to_h.deep_stringify_keys
      @shopclick_inputs = shopclick_inputs.to_h.deep_stringify_keys
      @article_inputs = article_inputs.to_h.deep_stringify_keys
      @success_probability = normalize_probability(success_probability)
    end

    def call
      value = (estimated_incremental_clicks * value_per_click_yen).round

      Result.new(
        expected_profit_yen: value,
        metadata: {
          "value_model" => value_model_metadata(value),
          "suelog_article_value_model" => value_model_metadata(value),
          "gsc_inputs" => gsc_metadata,
          "ga4_inputs" => ga4_metadata,
          "shopclick_inputs" => shopclick_metadata,
          "business_metric_inputs" => business_metric_metadata,
          "estimated_incremental_clicks" => estimated_incremental_clicks.to_f.round(2),
          "estimated_shop_visits" => estimated_shop_visits.to_f.round(2),
          "estimated_booking_clicks" => estimated_booking_clicks.to_f.round(2),
          "expected_profit_yen" => value,
          "calculation_reason" => calculation_reason
        }
      )
    end

    private

    attr_reader :business, :query, :gsc_inputs, :ga4_inputs, :shopclick_inputs, :article_inputs, :success_probability

    def value_model_metadata(value)
      {
        "name" => "suelog_article",
        "calculation_version" => CALCULATION_VERSION,
        "formula" => "estimated_incremental_clicks * value_per_click_yen",
        "query" => query,
        "estimated_incremental_clicks" => estimated_incremental_clicks.to_f.round(2),
        "estimated_shop_visits" => estimated_shop_visits.to_f.round(2),
        "estimated_booking_clicks" => estimated_booking_clicks.to_f.round(2),
        "value_per_click_yen" => value_per_click_yen.to_f.round(2),
        "value_per_shop_click_yen" => value_per_shop_click_yen.to_f.round(2),
        "raw_expected_value_yen" => value,
        "final_expected_value_yen" => value,
        "expected_profit_yen" => value,
        "confidence" => confidence,
        "evidence_level" => evidence_level,
        "outlier_ratio" => 1,
        "valuation_review_required" => false,
        "success_probability" => success_probability&.to_f&.round(4),
        "calculated_at" => Time.current.iso8601
      }.compact
    end

    def gsc_metadata
      {
        "query" => query,
        "impressions" => impressions,
        "clicks" => clicks,
        "current_ctr" => current_ctr.to_f.round(4),
        "target_ctr" => target_ctr.to_f.round(4),
        "ctr_lift" => ctr_lift.to_f.round(4),
        "position" => position&.to_f&.round(2),
        "landing_page" => gsc_inputs["landing_page"].presence
      }.compact
    end

    def ga4_metadata
      {
        "pageviews" => first_numeric(ga4_inputs["pageviews"], ga4_inputs["views"]),
        "active_users" => first_numeric(ga4_inputs["active_users"], ga4_inputs["users"]),
        "engagement_seconds" => first_numeric(ga4_inputs["engagement_seconds"], ga4_inputs["average_engagement_time_seconds"]),
        "article_to_shop_transitions" => first_numeric(ga4_inputs["article_to_shop_transitions"], ga4_inputs["internal_clicks"])
      }.compact
    end

    def shopclick_metadata
      {
        "recent_shop_clicks" => first_numeric(shopclick_inputs["recent_shop_clicks"], shopclick_inputs["clicks"]),
        "matched_shop_count" => first_numeric(shopclick_inputs["matched_shop_count"], shopclick_inputs["shop_count"]),
        "lookback_days" => first_numeric(shopclick_inputs["lookback_days"])
      }.compact
    end

    def business_metric_metadata
      model = suelog_value_model
      model.slice(
        "source",
        "lookback_days",
        "business_clicks_90d",
        "phone_clicks_90d",
        "map_clicks_90d",
        "affiliate_clicks_90d",
        "near_conversion_count_90d",
        "near_conversion_proxy_value_90d",
        "value_per_click_yen",
        "value_per_shop_click_yen",
        "high_confidence"
      )
    end

    def calculation_reason
      [
        "GSCの表示回数・CTR・順位から増加クリックを推定",
        "BusinessMetricDailyの電話/地図/予約クリックをProxyScoreWeightで円換算",
        "SERPやBusiness全体価値は記事期待値へ加算しない"
      ].join(" / ")
    end

    def estimated_incremental_clicks
      @estimated_incremental_clicks ||= (impressions.to_d * ctr_lift).round(2)
    end

    def estimated_shop_visits
      @estimated_shop_visits ||= begin
        return 0.to_d if value_per_shop_click_yen.zero?

        (estimated_incremental_clicks * value_per_click_yen / value_per_shop_click_yen).round(2)
      end
    end

    def estimated_booking_clicks
      @estimated_booking_clicks ||= (estimated_shop_visits * affiliate_click_share).round(2)
    end

    def affiliate_click_share
      near_conversion_count = suelog_value_model["near_conversion_count_90d"].to_i
      return 0.to_d if near_conversion_count.zero?

      suelog_value_model["affiliate_clicks_90d"].to_d / near_conversion_count
    end

    def impressions
      @impressions ||= first_numeric(gsc_inputs["impressions"], article_inputs["impressions"]).to_i
    end

    def clicks
      @clicks ||= first_numeric(gsc_inputs["clicks"], article_inputs["clicks"]).to_i
    end

    def current_ctr
      @current_ctr ||= begin
        value = first_numeric(gsc_inputs["ctr"], gsc_inputs["current_ctr"], article_inputs["ctr"])
        value = clicks.to_d / impressions if value.zero? && impressions.positive?
        normalize_ctr(value)
      end
    end

    def target_ctr
      @target_ctr ||= begin
        provided = first_numeric(gsc_inputs["target_ctr"], article_inputs["target_ctr"])
        return normalize_ctr(provided) if provided.positive?

        baseline =
          if position&.positive? && position <= 5
            0.035.to_d
          elsif position&.positive? && position <= 10
            0.025.to_d
          elsif position&.positive? && position <= 30
            0.015.to_d
          else
            0.01.to_d
          end
        [ baseline, current_ctr + 0.005.to_d ].max
      end
    end

    def ctr_lift
      @ctr_lift ||= [ target_ctr - current_ctr, 0.to_d ].max
    end

    def position
      @position ||= begin
        value = first_numeric(gsc_inputs["position"], gsc_inputs["average_position"], article_inputs["position"])
        value.positive? ? value : nil
      end
    end

    def value_per_click_yen
      @value_per_click_yen ||= suelog_value_model.fetch("value_per_click_yen").to_d
    end

    def value_per_shop_click_yen
      @value_per_shop_click_yen ||= suelog_value_model.fetch("value_per_shop_click_yen").to_d
    end

    def suelog_value_model
      @suelog_value_model ||= begin
        metrics = business.business_metric_dailies.where(recorded_on: 90.days.ago.to_date..Date.current)
        clicks = metrics.sum(:clicks).to_i
        phone_clicks = metrics.sum(:phone_clicks).to_i
        map_clicks = metrics.sum(:map_clicks).to_i
        affiliate_clicks = metrics.sum(:affiliate_clicks).to_i
        near_conversion_count = phone_clicks + map_clicks + affiliate_clicks
        weights = ProxyScoreWeight.for_business(business)
        near_conversion_value =
          (phone_clicks * weights.weight_for(:phone_clicks).to_d) +
          (map_clicks * weights.weight_for(:map_clicks).to_d) +
          (affiliate_clicks * weights.weight_for(:affiliate_clicks).to_d)
        value_per_click = clicks.positive? && near_conversion_value.positive? ? near_conversion_value / clicks : 8.to_d
        value_per_shop_click = near_conversion_count.positive? ? near_conversion_value / near_conversion_count : 12.to_d

        {
          "source" => "business_metric_dailies_90d_and_suelog_shop_clicks",
          "lookback_days" => 90,
          "business_clicks_90d" => clicks,
          "phone_clicks_90d" => phone_clicks,
          "map_clicks_90d" => map_clicks,
          "affiliate_clicks_90d" => affiliate_clicks,
          "near_conversion_count_90d" => near_conversion_count,
          "near_conversion_proxy_value_90d" => near_conversion_value.round(2).to_s,
          "value_per_click_yen" => clamp_decimal(value_per_click, min: 2, max: 80).round(2).to_s,
          "value_per_shop_click_yen" => clamp_decimal(value_per_shop_click, min: 5, max: 120).round(2).to_s,
          "high_confidence" => clicks >= 100 && near_conversion_count >= 5
        }
      end
    end

    def confidence
      suelog_value_model["high_confidence"] ? 0.65 : 0.35
    end

    def evidence_level
      suelog_value_model["high_confidence"] ? "medium" : "low"
    end

    def normalize_ctr(value)
      value = value.to_d
      value > 1 ? value / 100 : value
    end

    def normalize_probability(value)
      return nil if value.blank?

      probability = value.to_d
      probability > 1 ? probability / 100 : probability
    end

    def first_numeric(*values)
      values.each do |value|
        next if value.blank?

        decimal = value.to_d
        return decimal if decimal.positive?
      end
      0.to_d
    end

    def clamp_decimal(value, min:, max:)
      [[ value.to_d, min.to_d ].max, max.to_d].min
    end
  end
end

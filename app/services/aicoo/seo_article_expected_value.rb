module Aicoo
  class SeoArticleExpectedValue
    ARTICLE_ACTION_TYPES = %w[seo_article new_article_candidate article_create].freeze
    CALCULATION_VERSION = "seo_article_incremental_uncapped_v1".freeze

    Result = Data.define(:raw_expected_value_yen, :final_expected_value_yen, :metadata)

    class << self
      def call(candidate)
        new(candidate).call
      end

      def applies_to?(candidate)
        candidate.action_type.to_s.in?(ARTICLE_ACTION_TYPES) ||
          candidate.metadata.to_h["work_type"].to_s.in?(%w[new_article article_create])
      end
    end

    def initialize(candidate)
      @candidate = candidate
      @metadata = candidate.metadata.to_h.deep_stringify_keys
    end

    def call
      raw_value = calculation_ready? ? (estimated_incremental_clicks * conversion_rate * profit_per_conversion * success_probability).round : 0
      final_value = raw_value
      Result.new(
        raw_expected_value_yen: raw_value,
        final_expected_value_yen: final_value,
        metadata: merged_metadata(raw_value:, final_value:)
      )
    end

    private

    attr_reader :candidate, :metadata

    def merged_metadata(raw_value:, final_value:)
      metadata.except("cap_applied", "cap_reason", "seo_expected_value_cap_yen").merge(
        "estimated_incremental_clicks" => estimated_incremental_clicks.to_f.round(2),
        "estimated_rank_delta" => estimated_rank_delta&.to_f&.round(2),
        "estimated_ctr_delta" => estimated_ctr_delta.to_f.round(4),
        "conversion_rate" => conversion_rate&.to_f&.round(4),
        "profit_per_conversion" => profit_per_conversion&.to_f&.round(2),
        "profit_per_conversion_yen" => profit_per_conversion&.to_f&.round(2),
        "success_probability" => success_probability&.to_f&.round(4),
        "seo_expected_value_cap" => nil,
        "raw_expected_value" => raw_value,
        "uncapped_expected_value_yen" => raw_value,
        "final_expected_value" => final_value,
        "final_expected_value_yen" => final_value,
        "calculation_status" => calculation_status,
        "review_required" => review_required?,
        "input_source" => input_source,
        "seo_article_value_model" => {
          "calculation_version" => CALCULATION_VERSION,
          "formula" => "incremental_clicks * conversion_rate * profit_per_conversion * success_probability",
          "estimated_incremental_clicks" => estimated_incremental_clicks.to_f.round(2),
          "estimated_rank_delta" => estimated_rank_delta&.to_f&.round(2),
          "estimated_ctr_delta" => estimated_ctr_delta.to_f.round(4),
          "current_position" => current_position&.to_f&.round(2),
          "target_position" => target_position&.to_f&.round(2),
          "current_ctr" => current_ctr&.to_f&.round(4),
          "target_ctr" => target_ctr.to_f.round(4),
          "impressions" => impressions.to_f.round(2),
          "conversion_rate" => conversion_rate&.to_f&.round(4),
          "profit_per_conversion" => profit_per_conversion&.to_f&.round(2),
          "profit_per_conversion_yen" => profit_per_conversion&.to_f&.round(2),
          "success_probability" => success_probability&.to_f&.round(4),
          "revenue_event_available" => revenue_event_available?,
          "cap_yen" => nil,
          "cap_applied" => false,
          "cap_reason" => nil,
          "excluded_value_sources" => %w[learning judge business_expected_value],
          "input_source" => input_source,
          "missing_inputs" => missing_inputs,
          "calculation_status" => calculation_status,
          "review_required" => review_required?,
          "uncapped_expected_value_yen" => raw_value,
          "raw_expected_value_yen" => raw_value,
          "final_expected_value_yen" => final_value,
          "calculated_at" => Time.current.iso8601
        },
        "action_value_model" => metadata.fetch("action_value_model", {}).to_h.merge(
          "expected_value_if_no_action_yen" => 0,
          "expected_value_if_action_yen" => final_value,
          "execution_cost_yen" => candidate.cost_yen.to_i,
          "action_expected_value_delta_yen" => final_value - candidate.cost_yen.to_i,
          "valuation_period_days" => 90,
          "calculation_method" => CALCULATION_VERSION,
          "confidence" => success_probability.to_f.round(4)
        )
      )
    end

    def estimated_incremental_clicks
      @estimated_incremental_clicks ||= [
        impressions * estimated_ctr_delta,
        0.to_d
      ].max
    end

    def estimated_rank_delta
      return nil if current_position.blank? || target_position.blank?

      current_position.to_d - target_position.to_d
    end

    def estimated_ctr_delta
      @estimated_ctr_delta ||= [
        target_ctr.to_d - current_ctr.to_d,
        0.to_d
      ].max
    end

    def impressions
      @impressions ||= decimal_from(
        metadata["impressions"],
        metadata.dig("gsc", "impressions"),
        metadata.dig("gsc_metrics", "impressions"),
        metadata.dig("supporting_metrics", "impressions"),
        metadata.dig("opportunity", "supporting_metrics", "impressions"),
        metadata["expected_pv"],
        fallback: 0
      )
    end

    def current_ctr
      @current_ctr ||= begin
        explicit = ratio_from(
          metadata["current_ctr"],
          metadata["ctr"],
          metadata.dig("gsc", "ctr"),
          metadata.dig("gsc_metrics", "ctr"),
          metadata.dig("supporting_metrics", "ctr"),
          metadata.dig("opportunity", "supporting_metrics", "ctr")
        )
        explicit || ctr_for_position(current_position) || 0.to_d
      end
    end

    def target_ctr
      @target_ctr ||= begin
        explicit = ratio_from(
          metadata["target_ctr"],
          metadata["estimated_target_ctr"],
          metadata.dig("value_model", "target_ctr"),
          metadata.dig("seo_article_value_model", "target_ctr")
        )
        explicit || ctr_for_position(target_position) || current_ctr
      end
    end

    def current_position
      @current_position ||= decimal_from(
        metadata["current_position"],
        metadata["position"],
        metadata["average_position"],
        metadata["avg_position"],
        metadata.dig("gsc", "position"),
        metadata.dig("gsc", "average_position"),
        metadata.dig("gsc_metrics", "position"),
        metadata.dig("gsc_metrics", "average_position"),
        metadata.dig("supporting_metrics", "position"),
        fallback: nil
      )
    end

    def target_position
      @target_position ||= decimal_from(
        metadata["target_position"],
        metadata.dig("value_model", "target_position"),
        metadata.dig("seo_article_value_model", "target_position"),
        fallback: inferred_target_position
      )
    end

    def inferred_target_position
      return nil if current_position.blank?

      current = current_position.to_d
      if current <= 5
        [ current - 1, 3 ].max
      elsif current <= 10
        [ current - 2, 5 ].max
      else
        10
      end
    end

    def conversion_rate
      @conversion_rate ||= ratio_from(
        metadata["conversion_rate"],
        metadata["cv_rate"],
        metadata.dig("value_model", "conversion_rate"),
        metadata.dig("seo_article_value_model", "conversion_rate")
      )
    end

    def profit_per_conversion
      @profit_per_conversion ||= begin
        explicit = decimal_from(
          metadata["profit_per_conversion"],
          metadata["profit_per_conversion_yen"],
          metadata["profit_per_cv"],
          metadata["value_per_conversion"],
          metadata.dig("value_model", "profit_per_conversion"),
          metadata.dig("seo_article_value_model", "profit_per_conversion_yen"),
          metadata.dig("seo_article_value_model", "profit_per_conversion"),
          fallback: nil
        )
        explicit || revenue_event_average_amount
      end
    end

    def success_probability
      @success_probability ||= begin
        explicit = ratio_from(
          metadata["success_probability"],
          metadata.dig("value_model", "success_probability"),
          metadata.dig("seo_article_value_model", "success_probability")
        )
        candidate_probability = candidate.success_probability.to_d
        explicit.presence || (candidate_probability.positive? ? candidate_probability : nil)
      end
    end

    def revenue_event_available?
      @revenue_event_available = candidate.business&.revenue_events&.revenue&.exists? if @revenue_event_available.nil?
      @revenue_event_available == true
    rescue StandardError
      false
    end

    def revenue_event_average_amount
      return nil unless revenue_event_available?

      candidate.business.revenue_events.revenue.average(:amount)&.to_d
    end

    def calculation_ready?
      missing_inputs.empty?
    end

    def calculation_status
      calculation_ready? ? "calculated" : "insufficient_data"
    end

    def review_required?
      !calculation_ready?
    end

    def missing_inputs
      @missing_inputs ||= begin
        missing = []
        missing << "estimated_incremental_clicks" unless estimated_incremental_clicks.positive?
        missing << "conversion_rate" if conversion_rate.blank?
        missing << "profit_per_conversion_yen" if profit_per_conversion.blank?
        missing << "success_probability" if success_probability.blank?
        missing
      end
    end

    def input_source
      {
        "impressions" => input_source_for(:impressions),
        "current_ctr" => input_source_for(:current_ctr),
        "target_ctr" => input_source_for(:target_ctr),
        "conversion_rate" => input_source_for(:conversion_rate),
        "profit_per_conversion_yen" => revenue_event_average_amount.present? ? "revenue_events.average_amount" : input_source_for(:profit_per_conversion),
        "success_probability" => input_source_for(:success_probability)
      }
    end

    def input_source_for(input)
      case input
      when :impressions
        return "metadata.impressions" if metadata["impressions"].present?
        return "metadata.gsc.impressions" if metadata.dig("gsc", "impressions").present?
        return "metadata.gsc_metrics.impressions" if metadata.dig("gsc_metrics", "impressions").present?
        return "metadata.supporting_metrics.impressions" if metadata.dig("supporting_metrics", "impressions").present?
        return "metadata.expected_pv" if metadata["expected_pv"].present?
      when :current_ctr
        return "metadata.current_ctr" if metadata["current_ctr"].present?
        return "metadata.ctr" if metadata["ctr"].present?
        return "metadata.gsc.ctr" if metadata.dig("gsc", "ctr").present?
        return "position_curve" if current_position.present?
      when :target_ctr
        return "metadata.target_ctr" if metadata["target_ctr"].present?
        return "metadata.estimated_target_ctr" if metadata["estimated_target_ctr"].present?
        return "position_curve" if target_position.present?
      when :conversion_rate
        return "metadata.conversion_rate" if metadata["conversion_rate"].present?
        return "metadata.cv_rate" if metadata["cv_rate"].present?
        return "metadata.value_model.conversion_rate" if metadata.dig("value_model", "conversion_rate").present?
      when :profit_per_conversion
        return "metadata.profit_per_conversion_yen" if metadata["profit_per_conversion_yen"].present?
        return "metadata.profit_per_conversion" if metadata["profit_per_conversion"].present?
        return "metadata.profit_per_cv" if metadata["profit_per_cv"].present?
        return "metadata.value_per_conversion" if metadata["value_per_conversion"].present?
        return "metadata.value_model.profit_per_conversion" if metadata.dig("value_model", "profit_per_conversion").present?
      when :success_probability
        return "metadata.success_probability" if metadata["success_probability"].present?
        return "metadata.value_model.success_probability" if metadata.dig("value_model", "success_probability").present?
        return "action_candidate.success_probability" if candidate.success_probability.to_d.positive?
      end

      "missing"
    end

    def ctr_for_position(position)
      return nil if position.blank?

      position = position.to_d
      case position
      when 0...1.5 then 0.28.to_d
      when 1.5...2.5 then 0.15.to_d
      when 2.5...3.5 then 0.10.to_d
      when 3.5...4.5 then 0.07.to_d
      when 4.5...5.5 then 0.05.to_d
      when 5.5...6.5 then 0.04.to_d
      when 6.5...7.5 then 0.035.to_d
      when 7.5...8.5 then 0.03.to_d
      when 8.5...9.5 then 0.025.to_d
      when 9.5...10.5 then 0.02.to_d
      when 10.5...20.5 then 0.015.to_d
      else 0.01.to_d
      end
    end

    def ratio_from(*values, fallback: nil)
      value = decimal_from(*values, fallback:)
      return value if value.blank? || value <= 1

      value / 100
    end

    def decimal_from(*values, fallback:)
      values.flatten.compact_blank.each do |value|
        begin
          return value.to_d if value.respond_to?(:to_d)
        rescue ArgumentError
          next
        end
      end
      fallback&.to_d
    end
  end
end

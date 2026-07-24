module Aicoo
  class BusinessExpectedValue
    NEW_BUSINESS_STANDARD_90D_PROFIT_YEN = 30_000
    NEW_BUSINESS_STANDARD_SUCCESS_PROBABILITY = 0.15.to_d
    NEW_BUSINESS_STANDARD_VALIDATION_COST_YEN = 5_000
    CALCULATION_VERSION = "business_expected_value_v1".freeze

    Result = Data.define(
      :business,
      :raw_candidate_sum_yen,
      :base_business_value_yen,
      :action_opportunity_value_yen,
      :unique_opportunity_count,
      :duplicate_candidate_count,
      :duplicate_adjustment_yen,
      :market_limit_adjustment_yen,
      :cannibalization_adjustment_yen,
      :confidence_adjustment_yen,
      :cost_yen,
      :expected_revenue_value_yen,
      :expected_learning_value_yen,
      :expected_total_value_yen,
      :calculation_method,
      :confidence,
      :opportunities,
      :base_business_value,
      :new_business_value
    )
    OpportunityRow = Data.define(
      :key,
      :raw_sum_yen,
      :market_limit_yen,
      :final_value_yen,
      :candidate_ids,
      :duplicate_candidate_count,
      :duplicate_adjustment_yen,
      :market_limit_adjustment_yen,
      :cannibalization_adjustment_yen,
      :confidence_adjustment_yen,
      :cost_yen,
      :input_values,
      :anomaly_detected,
      :anomaly_reason
    )
    NewBusinessValue = Data.define(
      :estimated_90d_profit_yen,
      :validation_success_probability,
      :validation_cost_yen,
      :final_expected_value_yen,
      :calculation_method,
      :confidence,
      :missing_inputs
    )
    BaseBusinessValue = Data.define(
      :base_business_value_yen,
      :source,
      :calculation_status,
      :observed_period_start,
      :observed_period_end,
      :observed_days,
      :normalized_to_90_days,
      :business_metric_inputs,
      :shop_click_inputs,
      :gsc_inputs,
      :ga4_inputs,
      :proxy_weight_inputs,
      :double_count_prevention,
      :source_model
    )

    def self.call(business, candidates: nil, persist: true)
      Aicoo::MemoryDiagnostics.measure(
        "Aicoo::BusinessExpectedValue.call",
        context: {
          business_id: business&.id,
          business_name: business&.name,
          business_type: business&.business_type,
          status: business&.status
        },
        finish: :warning_only
      ) do
        new(business, candidates:, persist:).call
      end
    end

    def initialize(business, candidates: nil, persist: true)
      @business = business
      @supplied_candidates = candidates
      @persist = persist
    end

    def call
      return new_business_result if exploration_business?

      existing_business_result
    end

    private

    attr_reader :business, :supplied_candidates, :persist

    def existing_business_result
      rows = grouped_opportunities.map { |key, candidates| build_opportunity_row(key, candidates) }
      raw_candidate_sum_yen = active_candidates.sum { |candidate| raw_candidate_value_yen(candidate) }
      duplicate_candidate_count = rows.sum(&:duplicate_candidate_count)
      duplicate_adjustment_yen = rows.sum(&:duplicate_adjustment_yen)
      opportunity_total_yen = rows.sum(&:final_value_yen)
      market_limit_adjustment_yen = rows.sum(&:market_limit_adjustment_yen)
      cannibalization_adjustment_yen = rows.sum(&:cannibalization_adjustment_yen)
      confidence_adjustment_yen = rows.sum(&:confidence_adjustment_yen)
      cost_yen = rows.sum(&:cost_yen)
      expected_revenue_value_yen = opportunity_total_yen - cost_yen
      expected_learning_value_yen = active_candidates.sum { |candidate| candidate.expected_learning_value_yen.to_i }
      action_opportunity_value_yen = expected_revenue_value_yen + expected_learning_value_yen
      base_value = existing_business_base_value_applies? ? base_business_value : empty_base_business_value
      expected_total_value_yen = base_value.base_business_value_yen + action_opportunity_value_yen

      result = Result.new(
        business:,
        raw_candidate_sum_yen:,
        base_business_value_yen: base_value.base_business_value_yen,
        action_opportunity_value_yen:,
        unique_opportunity_count: rows.size,
        duplicate_candidate_count:,
        duplicate_adjustment_yen:,
        market_limit_adjustment_yen:,
        cannibalization_adjustment_yen:,
        confidence_adjustment_yen:,
        cost_yen:,
        expected_revenue_value_yen:,
        expected_learning_value_yen:,
        expected_total_value_yen:,
        calculation_method: existing_business_base_value_applies? ? "existing_business_base_plus_actions" : "opportunity_grouped_market_limited_sum",
        confidence: rows.any? ? average(rows.map { |row| row.final_value_yen.positive? ? 0.7 : 0.4 }) : 0.3,
        opportunities: rows,
        base_business_value: base_value,
        new_business_value: nil
      )
      persist_business_value!(result)
      result
    end

    def new_business_result
      value = new_business_value
      result = Result.new(
        business:,
        raw_candidate_sum_yen: value.estimated_90d_profit_yen,
        base_business_value_yen: 0,
        action_opportunity_value_yen: value.final_expected_value_yen,
        unique_opportunity_count: 1,
        duplicate_candidate_count: 0,
        duplicate_adjustment_yen: 0,
        market_limit_adjustment_yen: 0,
        cannibalization_adjustment_yen: 0,
        confidence_adjustment_yen: ((value.estimated_90d_profit_yen.to_d * (1 - value.validation_success_probability)).round),
        cost_yen: value.validation_cost_yen,
        expected_revenue_value_yen: value.final_expected_value_yen,
        expected_learning_value_yen: 0,
        expected_total_value_yen: value.final_expected_value_yen,
        calculation_method: value.calculation_method,
        confidence: value.confidence,
        opportunities: [],
        base_business_value: nil,
        new_business_value: value
      )
      persist_business_value!(result)
      result
    end

    def active_candidates
      @active_candidates ||= begin
        candidates = supplied_candidates.nil? ? business.action_candidates.active_for_ranking.to_a : supplied_candidates
        candidates.reject { |candidate| invalid_url_candidate?(candidate) }
      end
    end

    def grouped_opportunities
      active_candidates.group_by { |candidate| opportunity_key_for(candidate) }
    end

    def build_opportunity_row(key, candidates)
      raw_sum_yen = candidates.sum { |candidate| raw_candidate_value_yen(candidate) }
      cost_yen = candidates.sum { |candidate| candidate.cost_yen.to_i }
      duplicate_base_yen = candidates.map { |candidate| raw_candidate_value_yen(candidate) }.max.to_i
      duplicate_adjustment_yen = candidates.size > 1 ? [ raw_sum_yen - duplicate_base_yen, 0 ].max : 0
      confidence_adjusted_values = candidates.to_h do |candidate|
        value = raw_candidate_value_yen(candidate)
        [ candidate, (value.to_d * confidence_for(candidate)).round ]
      end
      confidence_adjusted_sum = if candidates.size > 1
        confidence_adjusted_values.values.max.to_i
      else
        confidence_adjusted_values.values.sum
      end
      confidence_adjustment_yen = raw_sum_yen - duplicate_adjustment_yen - confidence_adjusted_sum
      input_values = opportunity_input_values(candidates)
      market_limit_yen = market_limit_yen_for(input_values)
      market_limited_value_yen = market_limit_yen ? [ confidence_adjusted_sum, market_limit_yen ].min : confidence_adjusted_sum
      market_limit_adjustment_yen = market_limit_yen ? [ confidence_adjusted_sum - market_limited_value_yen, 0 ].max : 0
      cannibalization_adjustment_yen = cannibalization_adjustment_yen_for(candidates, market_limited_value_yen)
      final_value_yen = market_limited_value_yen - cannibalization_adjustment_yen
      anomaly = anomaly_for(raw_sum_yen:, final_value_yen:, input_values:, candidates:)

      row = OpportunityRow.new(
        key:,
        raw_sum_yen:,
        market_limit_yen:,
        final_value_yen:,
        candidate_ids: candidates.map(&:id),
        duplicate_candidate_count: [ candidates.size - 1, 0 ].max,
        duplicate_adjustment_yen:,
        market_limit_adjustment_yen:,
        cannibalization_adjustment_yen:,
        confidence_adjustment_yen:,
        cost_yen:,
        input_values:,
        anomaly_detected: anomaly[:detected],
        anomaly_reason: anomaly[:reason]
      )
      persist_candidate_value_models!(key, candidates, row)
      row
    end

    def raw_candidate_value_yen(candidate)
      metadata = candidate.metadata.to_h
      metadata.dig("value_model", "raw_expected_value_yen").presence&.to_i ||
        metadata["raw_expected_value_yen"].presence&.to_i ||
        candidate.expected_profit_yen.to_i
    end

    def confidence_for(candidate)
      metadata = candidate.metadata.to_h
      value_model = metadata["value_model"].to_h
      confidence = value_model["confidence"].presence || candidate.success_probability.presence || 0.5
      confidence.to_d.clamp(0.1.to_d, 1.to_d)
    end

    def opportunity_key_for(candidate)
      metadata = candidate.metadata.to_h
      raw_key = [
        metadata["opportunity_group"],
        metadata["opportunity_key"],
        metadata.dig("opportunity", "key"),
        metadata.dig("evidence", "query"),
        metadata["query"],
        metadata["keyword"],
        metadata["source_query"],
        metadata.dig("article_candidate", "keyword")
      ].compact_blank.first

      raw_key ||= [
        metadata["target_url"],
        metadata["target_url_or_identifier"],
        metadata.dig("action_plan", "target_url_or_identifier"),
        metadata.dig("action_plan", "target"),
        metadata["search_intent"],
        metadata.dig("evidence", "issue_type"),
        metadata["metric_rule"],
        metadata["serp_analysis_id"],
        metadata["gsc_opportunity_id"]
      ].compact_blank.first

      normalized = raw_key.presence || "#{candidate.action_type}:#{candidate.title}"
      normalized.downcase
        .unicode_normalize(:nfkc)
        .gsub(%r{https?://}, "")
        .gsub(/[[:space:]　]+/, "")
        .gsub(/[?#].*\z/, "")
        .presence || "unknown"
    end

    def invalid_url_candidate?(candidate)
      metadata = candidate.metadata.to_h
      return true if metadata["url_classification"].to_s.in?(%w[external_reference invalid])
      return true if metadata["target_url_type"].to_s.in?(%w[external_reference invalid])
      return false unless candidate.action_type.to_s.in?(%w[seo_improvement article_update])

      metadata["target_url"].blank? || metadata["target_url_type"].to_s == "proposed_new"
    end

    def persist_candidate_value_models!(key, candidates, row)
      return unless persist

      duplicate_ids = row.candidate_ids
      candidates.each do |candidate|
        metadata = candidate.metadata.to_h
        raw_value = raw_candidate_value_yen(candidate)
        payload = {
          "raw_expected_value_yen" => raw_value,
          "final_expected_value_yen" => row.final_value_yen,
          "calculation_method" => "opportunity_grouped_market_limited_sum",
          "opportunity_group" => key,
          "duplicate_candidates" => duplicate_ids - [ candidate.id ],
          "duplicate_adjustment_yen" => row.duplicate_adjustment_yen,
          "market_limit_yen" => row.market_limit_yen,
          "market_limit_adjustment_yen" => row.market_limit_adjustment_yen,
          "cannibalization_adjustment_yen" => row.cannibalization_adjustment_yen,
          "confidence_adjustment_yen" => row.confidence_adjustment_yen,
          "execution_cost_yen" => row.cost_yen,
          "target_period" => "90d",
          "input_values" => row.input_values,
          "anomaly_detected" => row.anomaly_detected,
          "anomaly_reason" => row.anomaly_reason,
          "review_required" => row.anomaly_detected,
          "calculation_version" => CALCULATION_VERSION
        }
        next if metadata["business_value_model"] == payload

        candidate.update_columns(
          metadata: metadata.merge("business_value_model" => payload),
          updated_at: Time.current
        )
      end
    end

    def persist_business_value!(result)
      return unless persist

      metadata = business.metadata.to_h
      payload = {
        "raw_candidate_sum_yen" => result.raw_candidate_sum_yen,
        "model_name" => result.base_business_value ? "existing_business_base_plus_actions" : nil,
        "business_state" => result.base_business_value ? "existing" : nil,
        "base_business_value_yen" => result.base_business_value_yen,
        "action_opportunity_value_yen" => result.action_opportunity_value_yen,
        "unique_opportunity_count" => result.unique_opportunity_count,
        "duplicate_candidate_count" => result.duplicate_candidate_count,
        "duplicate_adjustment_yen" => result.duplicate_adjustment_yen,
        "market_limit_adjustment_yen" => result.market_limit_adjustment_yen,
        "cannibalization_adjustment_yen" => result.cannibalization_adjustment_yen,
        "confidence_adjustment_yen" => result.confidence_adjustment_yen,
        "cost_yen" => result.cost_yen,
        "expected_revenue_value_yen" => result.expected_revenue_value_yen,
        "expected_learning_value_yen" => result.expected_learning_value_yen,
        "final_expected_value_yen" => result.expected_total_value_yen,
        "calculation_method" => result.calculation_method,
        "confidence" => result.confidence.to_f,
        "calculation_version" => CALCULATION_VERSION,
        "base_business_value" => base_business_payload(result.base_business_value),
        "new_business_value" => new_business_payload(result.new_business_value),
        "calculated_at" => Time.current.iso8601
      }.compact

      business.update_columns(
        metadata: metadata.merge("business_value_model" => payload),
        updated_at: Time.current
      )
    end

    def new_business_payload(value)
      return unless value

      {
        "estimated_90d_profit_yen" => value.estimated_90d_profit_yen,
        "validation_success_probability" => value.validation_success_probability.to_f,
        "validation_cost_yen" => value.validation_cost_yen,
        "final_expected_value_yen" => value.final_expected_value_yen,
        "calculation_method" => value.calculation_method,
        "confidence" => value.confidence,
        "missing_inputs" => value.missing_inputs
      }
    end

    def base_business_payload(value)
      return unless value

      {
        "source_model" => value.source_model,
        "base_business_value_yen" => value.base_business_value_yen,
        "base_value_source" => value.source,
        "base_calculation_status" => value.calculation_status,
        "observed_period_start" => value.observed_period_start&.iso8601,
        "observed_period_end" => value.observed_period_end&.iso8601,
        "observed_days" => value.observed_days,
        "normalized_to_90_days" => value.normalized_to_90_days,
        "business_metric_inputs" => value.business_metric_inputs,
        "shop_click_inputs" => value.shop_click_inputs,
        "gsc_inputs" => value.gsc_inputs,
        "ga4_inputs" => value.ga4_inputs,
        "proxy_weight_inputs" => value.proxy_weight_inputs,
        "double_count_prevention" => value.double_count_prevention
      }.compact
    end

    def new_business_value
      metadata = business.metadata.to_h
      missing_inputs = []
      estimated_90d_profit_yen = first_positive_integer(
        metadata["estimated_90d_profit_yen"],
        metadata["expected_90d_profit_yen"],
        metadata["expected_value_yen"],
        metadata["expected_profit_yen"]
      )
      unless estimated_90d_profit_yen.positive?
        missing_inputs << "estimated_90d_profit_yen"
        estimated_90d_profit_yen = NEW_BUSINESS_STANDARD_90D_PROFIT_YEN
      end

      success_probability = first_positive_decimal(metadata["validation_success_probability"], metadata["success_probability"])
      unless success_probability.positive?
        missing_inputs << "validation_success_probability"
        success_probability = NEW_BUSINESS_STANDARD_SUCCESS_PROBABILITY
      end

      validation_cost_yen = first_positive_integer(metadata["validation_cost_yen"], metadata["initial_cost_yen"])
      unless validation_cost_yen.positive?
        missing_inputs << "validation_cost_yen"
        validation_cost_yen = NEW_BUSINESS_STANDARD_VALIDATION_COST_YEN
      end

      final_expected_value_yen = (estimated_90d_profit_yen.to_d * success_probability - validation_cost_yen).round

      NewBusinessValue.new(
        estimated_90d_profit_yen:,
        validation_success_probability: success_probability,
        validation_cost_yen:,
        final_expected_value_yen:,
        calculation_method: missing_inputs.empty? ? "new_business_metadata" : "new_business_fallback_standard_90d",
        confidence: missing_inputs.empty? ? "medium" : "low",
        missing_inputs:
      )
    end

    def exploration_business?
      business.business_type == "exploration" || business.status.in?(%w[discovered draft exploring])
    end

    def existing_business_base_value_applies?
      return false if exploration_business?

      business.status.to_s.in?(%w[launched active]) || business.launched?
    end

    def suelog_business?
      metadata = business.metadata.to_h
      keys = [
        business.name,
        business.business_type,
        business.project_key,
        business.repository_name,
        business.local_project_path,
        business.source,
        business.gsc_site_url,
        metadata["source_app"],
        metadata["source_system"],
        metadata["business_key"],
        metadata["slug"],
        metadata["project_key"]
      ].compact.map(&:to_s)
      keys.any? { |value| value.match?(/吸えログ|suelog|sue-log/i) }
    end

    def empty_base_business_value
      BaseBusinessValue.new(
        base_business_value_yen: 0,
        source: "not_applicable",
        calculation_status: "not_applicable",
        observed_period_start: nil,
        observed_period_end: nil,
        observed_days: 0,
        normalized_to_90_days: false,
        business_metric_inputs: {},
        shop_click_inputs: {},
        gsc_inputs: {},
        ga4_inputs: {},
        proxy_weight_inputs: {},
        double_count_prevention: "base value not applied to this business state",
        source_model: nil
      )
    end

    def base_business_value
      @base_business_value ||= begin
        revenue_yen = measured_profit_yen
        metric_inputs = business_metric_inputs
        source = nil
        status = nil
        base_yen = 0

        if revenue_yen.positive?
          base_yen = revenue_yen
          source = measured_profit_source
          status = "actual_profit"
        elsif metric_inputs["near_conversion_proxy_value_90d"].to_d.positive?
          base_yen = metric_inputs["near_conversion_proxy_value_90d"].to_d.round
          source = "business_metric_dailies_proxy_weighted_clicks"
          status = "proxy_weighted_conversions"
        else
          source = "traffic_without_monetization"
          status = "insufficient_monetization_data"
        end

        BaseBusinessValue.new(
          base_business_value_yen: base_yen,
          source:,
          calculation_status: status,
          observed_period_start: observed_period_start,
          observed_period_end: observed_period_end,
          observed_days: observed_days,
          normalized_to_90_days: false,
          business_metric_inputs: metric_inputs.merge("measured_profit_yen" => revenue_yen),
          shop_click_inputs: shop_click_inputs,
          gsc_inputs: gsc_inputs(metric_inputs),
          ga4_inputs: ga4_inputs(metric_inputs),
          proxy_weight_inputs: proxy_weight_inputs,
          double_count_prevention: base_double_count_prevention(source),
          source_model: suelog_business? ? "suelog_existing_business" : "existing_business"
        )
      end
    end

    def measured_profit_yen
      revenue = revenue_events_profit_yen
      return revenue if revenue.positive?

      business_metric_profit_yen
    end

    def measured_profit_source
      return "revenue_events_90d" if revenue_events_profit_yen.positive?
      return "business_metric_dailies_measured_profit_90d" if business_metric_profit_yen.positive?

      "none"
    end

    def revenue_events_profit_yen
      return 0 unless business.respond_to?(:revenue_events)

      business.revenue_events.where(occurred_on: lookback_range).sum(:amount).to_i
    end

    def business_metric_profit_yen
      metrics = recent_business_metrics
      total = 0
      total += metrics.sum(:profit_yen).to_i if BusinessMetricDaily.column_names.include?("profit_yen")
      total += metrics.sum(:revenue_yen).to_i if BusinessMetricDaily.column_names.include?("revenue_yen")
      total
    end

    def business_metric_inputs
      @business_metric_inputs ||= begin
        metrics = recent_business_metrics
        weights = ProxyScoreWeight.for_business(business)
        phone_clicks = metrics.sum(:phone_clicks).to_i
        map_clicks = metrics.sum(:map_clicks).to_i
        affiliate_clicks = metrics.sum(:affiliate_clicks).to_i
        near_conversion_count = phone_clicks + map_clicks + affiliate_clicks
        near_conversion_value =
          (phone_clicks * weights.weight_for(:phone_clicks).to_d) +
          (map_clicks * weights.weight_for(:map_clicks).to_d) +
          (affiliate_clicks * weights.weight_for(:affiliate_clicks).to_d)

        {
          "source" => "business_metric_dailies_90d",
          "clicks" => metrics.sum(:clicks).to_i,
          "impressions" => metrics.sum(:impressions).to_i,
          "sessions" => metrics.sum(:sessions).to_i,
          "pageviews" => metrics.sum(:pageviews).to_i,
          "users" => metrics.sum(:users).to_i,
          "phone_clicks" => phone_clicks,
          "map_clicks" => map_clicks,
          "affiliate_clicks" => affiliate_clicks,
          "near_conversion_count" => near_conversion_count,
          "near_conversion_proxy_value_90d" => near_conversion_value.round(2).to_s,
          "observed_days" => observed_days
        }
      end
    end

    def shop_click_inputs
      @shop_click_inputs ||= begin
        if suelog_business? && defined?(::Suelog::ShopClick)
          scope = ::Suelog::ShopClick.where(created_at: lookback_start.beginning_of_day..lookback_end.end_of_day)
          columns = ::Suelog::ShopClick.column_names
          click_type_column = %w[click_type kind event_type action].find { |column| columns.include?(column) }
          counts = { "total_clicks" => scope.count }
          if click_type_column
            grouped = scope.group(click_type_column).count
            counts.merge!(
              "phone_clicks" => grouped.values_at("phone", "phone_click", "tel").compact.sum,
              "map_clicks" => grouped.values_at("map", "map_click").compact.sum,
              "affiliate_clicks" => grouped.values_at("affiliate", "affiliate_click", "reservation", "booking").compact.sum,
              "article_shop_clicks" => grouped.values_at("article_shop", "shop", "shop_click").compact.sum,
              "click_type_column" => click_type_column
            )
          end
          counts.merge("source" => "suelog_shop_clicks_90d")
        else
          { "source" => "not_available", "total_clicks" => 0 }
        end
      rescue StandardError => e
        { "source" => "suelog_shop_clicks_90d", "error" => e.class.name, "total_clicks" => 0 }
      end
    end

    def gsc_inputs(metric_inputs = business_metric_inputs)
      {
        "source" => "business_metric_dailies_90d",
        "clicks" => metric_inputs["clicks"].to_i,
        "impressions" => metric_inputs["impressions"].to_i,
        "used_for_profit" => false
      }
    end

    def ga4_inputs(metric_inputs = business_metric_inputs)
      {
        "source" => "business_metric_dailies_90d",
        "pageviews" => metric_inputs["pageviews"].to_i,
        "active_users" => metric_inputs["users"].to_i,
        "sessions" => metric_inputs["sessions"].to_i,
        "used_for_profit" => false
      }
    end

    def proxy_weight_inputs
      weights = ProxyScoreWeight.for_business(business)
      {
        "source_type" => weights.source_type,
        "confidence_score" => weights.confidence_score,
        "phone_clicks_weight" => weights.weight_for(:phone_clicks).to_f,
        "map_clicks_weight" => weights.weight_for(:map_clicks).to_f,
        "affiliate_clicks_weight" => weights.weight_for(:affiliate_clicks).to_f
      }
    end

    def base_double_count_prevention(source)
      if source == "business_metric_dailies_proxy_weighted_clicks"
        "base value uses BusinessMetricDaily conversion clicks; Suelog::ShopClick is evidence only and is not added"
      elsif source == "revenue_events_90d"
        "base value uses measured RevenueEvent amount first; click proxy values are evidence only"
      else
        "GSC/GA4 traffic is stored as evidence only and is not monetized without conversion or revenue data"
      end
    end

    def recent_business_metrics
      @recent_business_metrics ||= business.business_metric_dailies.where(recorded_on: lookback_range)
    end

    def observed_period_start
      @observed_period_start ||= recent_business_metrics.minimum(:recorded_on) || lookback_start
    end

    def observed_period_end
      @observed_period_end ||= recent_business_metrics.maximum(:recorded_on) || lookback_end
    end

    def observed_days
      @observed_days ||= recent_business_metrics.distinct.count(:recorded_on)
    end

    def lookback_range
      lookback_start..lookback_end
    end

    def lookback_start
      89.days.ago.to_date
    end

    def lookback_end
      Date.current
    end

    def first_positive_integer(*values)
      values.map { |value| value.to_i }.find(&:positive?) || 0
    end

    def first_positive_decimal(*values)
      values.map { |value| value.to_d }.find(&:positive?) || 0.to_d
    end

    def average(values)
      return 0.to_d if values.blank?

      values.sum.to_d / values.size
    end

    def opportunity_input_values(candidates)
      metadata_values = candidates.map { |candidate| candidate.metadata.to_h }
      impressions = first_positive_integer(*metadata_values.map { |metadata| dig_any(metadata, %w[impressions evidence.impressions opportunity.supporting_metrics.impressions]) })
      current_ctr = first_positive_decimal(*metadata_values.map { |metadata| dig_any(metadata, %w[current_ctr ctr evidence.current_ctr opportunity.supporting_metrics.current_ctr]) })
      benchmark_ctr = first_positive_decimal(*metadata_values.map { |metadata| dig_any(metadata, %w[benchmark_ctr target_ctr evidence.benchmark_ctr opportunity.supporting_metrics.benchmark_ctr]) })
      available_clicks = impressions.to_d * [ benchmark_ctr - current_ctr, 0.to_d ].max
      {
        "impressions" => impressions,
        "current_ctr" => current_ctr,
        "benchmark_ctr" => benchmark_ctr,
        "available_clicks" => available_clicks.round(2),
        "conversion_rate" => first_positive_decimal(*metadata_values.map { |metadata| dig_any(metadata, %w[conversion_rate cv_rate evidence.conversion_rate value_model.evidence.conversion_rate]) }),
        "profit_per_conversion" => first_positive_integer(*metadata_values.map { |metadata| dig_any(metadata, %w[profit_per_conversion profit_per_cv value_per_conversion value_model.evidence.profit_per_conversion]) }),
        "success_probability" => candidates.map { |candidate| candidate.success_probability.to_d }.max || 0.to_d,
        "target_period" => metadata_values.filter_map { |metadata| metadata["target_period"].presence || metadata.dig("value_model", "target_period").presence }.first || "90d"
      }
    end

    def market_limit_yen_for(input_values)
      impressions = input_values["impressions"].to_d
      return nil unless impressions.positive?

      current_ctr = input_values["current_ctr"].to_d
      benchmark_ctr = input_values["benchmark_ctr"].to_d
      return nil unless benchmark_ctr.positive?

      available_clicks = impressions * [ benchmark_ctr - current_ctr, 0.to_d ].max
      conversion_rate = input_values["conversion_rate"].presence&.to_d || 0.01.to_d
      profit_per_conversion = input_values["profit_per_conversion"].presence&.to_d || 500.to_d
      success_probability = input_values["success_probability"].presence&.to_d || 0.5.to_d
      (available_clicks * conversion_rate * profit_per_conversion * success_probability).round
    end

    def cannibalization_adjustment_yen_for(candidates, market_limited_value_yen)
      cannibalization_rates = candidates.filter_map { |candidate| candidate.metadata.to_h["cannibalization_rate"].presence&.to_d }
      return 0 if cannibalization_rates.blank?

      rate = cannibalization_rates.max.clamp(0.to_d, 0.9.to_d)
      (market_limited_value_yen.to_d * rate).round
    end

    def anomaly_for(raw_sum_yen:, final_value_yen:, input_values:, candidates:)
      reasons = []
      reasons << "raw_value_over_1m" if raw_sum_yen > 1_000_000
      reasons << "final_value_over_1m" if final_value_yen > 1_000_000
      reasons << "missing_market_inputs" if input_values["impressions"].to_i.zero? && raw_sum_yen > 1_000_000
      reasons << "large_duplicate_group" if candidates.size >= 5
      { detected: reasons.any?, reason: reasons.join(", ") }
    end

    def dig_any(hash, paths)
      paths.each do |path|
        value = path.split(".").reduce(hash) { |current, key| current.respond_to?(:[]) ? current[key] : nil }
        return value if value.present?
      end
      nil
    end
  end
end

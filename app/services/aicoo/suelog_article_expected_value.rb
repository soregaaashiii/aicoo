require "csv"
require "json"
require "uri"

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
          "source_query" => query.presence,
          "query_source" => query_source,
          "query_match_type" => gsc_query_match_type,
          "matched_query" => matched_gsc_query,
          "gsc_query_impressions" => impressions,
          "gsc_query_clicks" => clicks,
          "gsc_query_ctr" => current_ctr.to_f.round(4),
          "gsc_query_position" => position&.to_f&.round(2),
          "gsc_query_rows_count" => gsc_query_rows.size,
          "gsc_query_exact_count" => exact_query_rows.size,
          "gsc_query_normalized_count" => normalized_query_rows.size,
          "gsc_query_partial_count" => partial_query_rows.size,
          "gsc_search_models" => gsc_search_models,
          "gsc_search_tables" => gsc_search_tables,
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

    def gsc_diagnostics
      {
        "business_id" => business.id,
        "business_name" => business.name,
        "source_query" => query,
        "search_models" => gsc_search_models,
        "search_tables" => gsc_search_tables,
        "query_rows_count" => gsc_query_rows.size,
        "exact_count" => exact_query_rows.size,
        "normalized_count" => normalized_query_rows.size,
        "partial_count" => partial_query_rows.size,
        "matched_query" => matched_gsc_query,
        "match_type" => gsc_query_match_type,
        "fallback_reason" => gsc_fallback_reason,
        "query_rows" => gsc_query_rows
      }
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
        "landing_page" => resolved_gsc_inputs["landing_page"].presence,
        "query_match_type" => gsc_query_match_type,
        "matched_query" => matched_gsc_query,
        "query_source" => query_source,
        "query_rows_count" => gsc_query_rows.size,
        "exact_count" => exact_query_rows.size,
        "normalized_count" => normalized_query_rows.size,
        "partial_count" => partial_query_rows.size,
        "search_models" => gsc_search_models,
        "search_tables" => gsc_search_tables,
        "fallback_reason" => gsc_fallback_reason
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
      @impressions ||= first_numeric(resolved_gsc_inputs["impressions"], article_inputs["impressions"]).to_i
    end

    def clicks
      @clicks ||= first_numeric(resolved_gsc_inputs["clicks"], article_inputs["clicks"]).to_i
    end

    def current_ctr
      @current_ctr ||= begin
        value = first_numeric(resolved_gsc_inputs["ctr"], resolved_gsc_inputs["current_ctr"], article_inputs["ctr"])
        value = clicks.to_d / impressions if value.zero? && impressions.positive?
        normalize_ctr(value)
      end
    end

    def target_ctr
      @target_ctr ||= begin
        provided = first_numeric(resolved_gsc_inputs["target_ctr"], article_inputs["target_ctr"])
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
        value = first_numeric(resolved_gsc_inputs["position"], resolved_gsc_inputs["average_position"], article_inputs["position"])
        value.positive? ? value : nil
      end
    end

    def resolved_gsc_inputs
      @resolved_gsc_inputs ||= begin
        row = matched_query_row
        if row.present?
          {
            "query" => row["query"],
            "impressions" => first_numeric(row["impressions"]),
            "clicks" => first_numeric(row["clicks"]),
            "ctr" => first_numeric(row["ctr"], row["current_ctr"], row["ctr_percent"]),
            "position" => first_numeric(row["position"], row["average_position"]),
            "landing_page" => row["landing_page"].presence || row["page"].presence || row["url"].presence,
            "source" => row["source"].presence || "gsc_query_row",
            "query_match_type" => gsc_query_match_type
          }.compact
        else
          gsc_inputs.merge(
            "query" => query.presence,
            "query_match_type" => "fallback",
            "fallback_reason" => gsc_fallback_reason
          ).compact
        end
      end
    end

    def matched_query_row
      return @matched_query_row if defined?(@matched_query_row)

      @matched_query_row = nil
      return @matched_query_row if query.blank?

      exact = exact_query_rows.first
      if exact
        @gsc_query_match_type = "exact"
        @matched_query_row = exact
        return @matched_query_row
      end

      normalized = normalized_query_rows.first
      if normalized
        @gsc_query_match_type = "normalized"
        @matched_query_row = normalized
        return @matched_query_row
      end

      partial = partial_query_rows.first
      if partial
        @gsc_query_match_type = "partial"
        @matched_query_row = partial
        return @matched_query_row
      end

      @gsc_query_match_type = "fallback"
      @matched_query_row
    end

    def exact_query_rows
      @exact_query_rows ||= gsc_query_rows.select { |row| row["query"].to_s.squish == query }
    end

    def normalized_query_rows
      @normalized_query_rows ||= gsc_query_rows.select { |row| normalize_query(row["query"]) == normalized_query }
    end

    def partial_query_rows
      @partial_query_rows ||= gsc_query_rows.select { |row| partial_query_match?(row["query"]) }
    end

    def gsc_query_match_type
      matched_query_row unless defined?(@gsc_query_match_type)
      @gsc_query_match_type || "fallback"
    end

    def matched_gsc_query
      matched_query_row&.dig("query").presence
    end

    def query_source
      gsc_inputs["query_source"].presence || "argument_query"
    end

    def gsc_fallback_reason
      return nil unless gsc_query_match_type == "fallback"

      query.present? ? "gsc_query_row_not_found" : "source_query_blank"
    end

    def gsc_query_rows
      @gsc_query_rows ||= (gsc_rows_from_data_imports + gsc_rows_from_snapshots).filter_map do |row|
        normalized_gsc_row(row)
      end
    end

    def gsc_rows_from_data_imports
      return [] unless business.respond_to?(:data_sources)

      gsc_data_imports
        .sort_by { |data_import| [ data_import.imported_at || Time.zone.at(0), data_import.created_at || Time.zone.at(0) ] }
        .reverse
        .first(10)
        .flat_map { |data_import| rows_from_gsc_import(data_import) }
    end

    def gsc_data_imports
      imports = []
      imports.concat(
        business.data_sources
          .where(source_type: "gsc")
          .includes(:data_imports)
          .flat_map { |source| source.data_imports.recent.limit(3).to_a }
      )

      if matching_analytics_site_ids.any?
        imports.concat(
          DataImport
            .joins(:data_source)
            .where(data_sources: { source_type: "gsc" }, aicoo_analytics_site_id: matching_analytics_site_ids)
            .recent
            .limit(10)
            .to_a
        )
      end

      imports.uniq(&:id)
    end

    def rows_from_gsc_import(data_import)
      rows = rows_from_gsc_processed_text(data_import.processed_text)
      rows = rows_from_gsc_raw_text(data_import.raw_text) if rows.empty?
      rows
    end

    def rows_from_gsc_processed_text(processed_text)
      return [] if processed_text.blank?

      CSV.parse(processed_text, headers: true).filter_map do |row|
        query_value = value_from_row(row, "query", "検索クエリ", "keyword")
        next if query_value.blank?

        {
          "query" => query_value,
          "impressions" => numeric_value(value_from_row(row, "impressions", "表示回数")),
          "clicks" => numeric_value(value_from_row(row, "clicks", "クリック数")),
          "ctr" => ctr_value(value_from_row(row, "ctr", "CTR")),
          "position" => numeric_value(value_from_row(row, "position", "掲載順位", "平均掲載順位")),
          "landing_page" => value_from_row(row, "page", "ページ", "url"),
          "source" => "gsc_data_import",
          "source_model" => "DataImport",
          "source_table" => "data_imports"
        }
      end
    rescue CSV::MalformedCSVError
      []
    end

    def rows_from_gsc_raw_text(raw_text)
      return [] if raw_text.blank?

      parsed = JSON.parse(raw_text)
      Array(parsed["rows"]).filter_map do |row|
        row = row.to_h.deep_stringify_keys
        query_value = Array(row["keys"]).first.presence || row["query"].presence
        next if query_value.blank?

        {
          "query" => query_value,
          "impressions" => numeric_value(row["impressions"]),
          "clicks" => numeric_value(row["clicks"]),
          "ctr" => ctr_value(row["ctr"]),
          "position" => numeric_value(row["position"]),
          "landing_page" => row["page"].presence || row["url"].presence,
          "source" => "gsc_raw_import",
          "source_model" => "DataImport",
          "source_table" => "data_imports"
        }
      end
    rescue JSON::ParserError
      []
    end

    def gsc_rows_from_snapshots
      AicooDataSnapshot.where(source_type: "gsc").recent.limit(50).flat_map do |snapshot|
        payload = snapshot.payload.to_h.deep_stringify_keys
        next [] unless snapshot_belongs_to_business?(snapshot, payload)

        rows = payload["rows"] || payload.dig("metrics", "rows")
        rows = payload["metrics"] if rows.blank? && payload["metrics"].is_a?(Array)
        Array(rows).map do |row|
          row.to_h.deep_stringify_keys.merge(
            "source_model" => "AicooDataSnapshot",
            "source_table" => "aicoo_data_snapshots"
          )
        end
      end
    end

    def snapshot_belongs_to_business?(snapshot, payload)
      return true if payload["business_id"].present? && payload["business_id"].to_i == business.id
      return true if matching_analytics_site_ids.map(&:to_s).include?(payload["analytics_site_id"].to_s)
      return true if snapshot.source_id.to_i == business.id.to_i

      source_record = snapshot.source_record
      return true if source_record.respond_to?(:business_id) && source_record.business_id.to_i == business.id.to_i
      return true if source_record.respond_to?(:aicoo_analytics_site_id) && matching_analytics_site_ids.include?(source_record.aicoo_analytics_site_id)

      false
    end

    def normalized_gsc_row(row)
      row = row.to_h.deep_stringify_keys
      row_query = Array(row["keys"]).first.presence || row["query"].presence || row["keyword"].presence
      return nil if row_query.blank?

      {
        "query" => row_query.to_s.squish,
        "impressions" => first_numeric(row["impressions"], row["表示回数"]),
        "clicks" => first_numeric(row["clicks"], row["クリック数"]),
        "ctr" => first_numeric(row["ctr"], row["current_ctr"], row["ctr_percent"], row["CTR"]),
        "position" => first_numeric(row["position"], row["average_position"], row["掲載順位"], row["平均掲載順位"]),
        "landing_page" => row["landing_page"].presence || row["page"].presence || row["url"].presence || row["ページ"].presence,
        "source" => row["source"].presence || "gsc_snapshot",
        "source_model" => row["source_model"].presence,
        "source_table" => row["source_table"].presence
      }.compact
    end

    def partial_query_match?(row_query)
      row_normalized = normalize_query(row_query)
      return false if row_normalized.blank? || normalized_query.blank?
      return false if [ row_normalized.length, normalized_query.length ].min < 4

      row_normalized.include?(normalized_query) || normalized_query.include?(row_normalized)
    end

    def matching_analytics_site_ids
      @matching_analytics_site_ids ||= begin
        scopes = [ AicooAnalyticsSite.where(business_id: business.id) ]
        scopes << AicooAnalyticsSite.where(gsc_site_url: business.gsc_site_url) if business.gsc_site_url.present?
        domain_values.each do |domain|
          scopes << AicooAnalyticsSite.where(domain:)
          scopes << AicooAnalyticsSite.where("public_url ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(domain)}%")
        end

        scopes.flat_map { |scope| scope.pluck(:id) }.uniq
      end
    end

    def domain_values
      @domain_values ||= [
        domain_from_gsc_site_url(business.gsc_site_url),
        domain_from_url(business.metadata.to_h["production_url"]),
        domain_from_url(business.metadata.to_h["public_url"]),
        business.metadata.to_h["domain"]
      ].compact_blank.uniq
    end

    def domain_from_gsc_site_url(value)
      raw = value.to_s.strip
      return if raw.blank?

      raw.sub(/\Asc-domain:/, "").presence || domain_from_url(raw)
    end

    def domain_from_url(value)
      raw = value.to_s.strip
      return if raw.blank?

      URI.parse(raw.start_with?("http") ? raw : "https://#{raw}").host
    rescue URI::InvalidURIError
      nil
    end

    def gsc_search_models
      [
        "DataImport(data_sources.business_id)",
        ("DataImport(aicoo_analytics_site_id)" if matching_analytics_site_ids.any?),
        "AicooDataSnapshot"
      ].compact
    end

    def gsc_search_tables
      %w[data_imports data_sources aicoo_analytics_sites aicoo_data_snapshots]
    end

    def normalized_query
      @normalized_query ||= normalize_query(query)
    end

    def normalize_query(value)
      raw = value.to_s.squish
      return "" if raw.blank?

      if defined?(BusinessSerpKeyword)
        BusinessSerpKeyword.normalize(raw)
      else
        raw.downcase.gsub(/[[:space:]]+/, " ").strip
      end
    end

    def value_from_row(row, *keys)
      keys.lazy.map { |key| row[key] || row[key.to_s] || row[key.to_sym] }.find(&:present?)
    end

    def numeric_value(value)
      value.to_s.delete(",").to_d
    end

    def ctr_value(value)
      numeric = numeric_value(value)
      numeric > 1 ? numeric / 100 : numeric
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

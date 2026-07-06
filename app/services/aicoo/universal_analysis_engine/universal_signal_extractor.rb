module Aicoo
  module UniversalAnalysisEngine
    class UniversalSignalExtractor
      require "csv"

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current, limit: 20)
        @business = business
        @today = today.to_date
        @limit = limit
        @profile = Aicoo::BusinessCapabilityProfile.for(business)
      end

      def call
        (query_signals + aggregate_signals).uniq { |signal| [ signal.query, signal.page_path, signal.target_type, signal.source ] }
      end

      private

      attr_reader :business, :today, :limit, :profile

      def query_signals
        queries.first(limit).map do |query|
          build_signal(
            query:,
            page_path: latest_page_for(query),
            target_label: query,
            target_type: query_target_type(query),
            source: "query"
          )
        end
      end

      def aggregate_signals
        signals = []
        signals << build_signal(target_label: "流入上位ページ", target_type: "traffic_entry", source: "ga4_aggregate") if traffic.positive?
        signals << build_signal(target_label: profile.supply_assets.first || "主要資産", target_type: "asset", source: "business_db") if activity_count.positive? || profile.supply_assets.any?
        signals
      end

      def queries
        gsc_queries = latest_gsc_imports.flat_map { |data_import| queries_from_gsc_import(data_import) }
        metric_queries = impressions.positive? ? [ [ business.name, "比較" ].compact_blank.join(" ") ] : []

        (gsc_queries + metric_queries).compact_blank.uniq.first(limit)
      end

      def build_signal(query: nil, page_path: nil, target_label:, target_type:, source:)
        demand = demand_score_for(query)
        supply = supply_score_for(query || target_label)
        intent = conversion_intent_score_for(query || target_label)
        asset_match = asset_match_score_for(query || target_label)
        engagement = ga4_engagement_score
        work_cost = work_cost_for(target_type)
        expected_value = expected_value_for(demand:, supply:, intent:, asset_match:, engagement:)

        Signal.new(
          business:,
          query:,
          page_path:,
          asset_label: target_label,
          target_label:,
          target_type:,
          source:,
          impressions:,
          clicks:,
          ctr:,
          position: average_position,
          sessions:,
          pageviews:,
          conversions:,
          conversion_events: conversion_event_count,
          activity_count:,
          demand_score: demand.round(2),
          supply_score: supply.round(2),
          conversion_intent_score: intent.round(2),
          asset_match_score: asset_match.round(2),
          ga4_engagement_score: engagement.round(2),
          work_cost:,
          roi_score: work_cost.positive? ? (expected_value.to_d / work_cost).round(2) : 0,
          expected_value_yen: expected_value.to_i,
          metadata: {
            "profile" => profile.to_h,
            "query_classification" => query_classification_for(query || target_label),
            "recent_metric_days" => recent_metrics.size,
            "evidence_sources" => evidence_sources(source)
          }
        )
      end

      def recent_metrics
        @recent_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 29)..today).to_a
      end

      def impressions = recent_metrics.sum { |metric| metric.impressions.to_i }
      def clicks = recent_metrics.sum { |metric| metric.clicks.to_i }
      def sessions = recent_metrics.sum { |metric| metric.sessions.to_i }
      def pageviews = recent_metrics.sum { |metric| metric.pageviews.to_i }
      def conversions = recent_metrics.sum { |metric| metric.conversions.to_i }
      def conversion_event_count = recent_metrics.sum { |metric| metric.phone_clicks.to_i + metric.map_clicks.to_i + metric.affiliate_clicks.to_i + metric.event_count.to_i }
      def traffic = clicks + sessions + pageviews

      def ctr
        return 0.to_d if impressions.zero?

        clicks.to_d / impressions
      end

      def average_position
        values = recent_metrics.filter_map { |metric| metric.average_position.to_d if metric.average_position.to_d.positive? }
        return 0.to_d if values.empty?

        values.sum / values.size
      end

      def activity_count
        @activity_count ||= business.business_activity_logs.where(occurred_at: 30.days.ago..Time.current).count
      end

      def demand_score_for(query)
        base = impressions + (clicks * 5) + (pageviews * 0.5) + sessions
        query.present? ? [ base, 120 ].max : base
      end

      def supply_score_for(target)
        matching_activity = matching_activity_count(target)
        asset_base = profile.supply_assets.size * 4
        listing_boost = profile.has_listings ? 8 : 0
        article_boost = profile.has_articles ? 6 : 0

        [ matching_activity + asset_base + listing_boost + article_boost, 1 ].max
      end

      def matching_activity_count(target)
        normalized = target.to_s.downcase
        return 0 if normalized.blank?

        business.business_activity_logs
          .where(occurred_at: 180.days.ago..Time.current)
          .where("title ILIKE ? OR diff_summary ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(normalized)}%", "%#{ActiveRecord::Base.sanitize_sql_like(normalized)}%")
          .count
      end

      def conversion_intent_score_for(text)
        normalized = text.to_s.downcase
        rules = profile.intent_keywords.to_h
        return 1.0.to_d if normalized.blank?

        return 1.45.to_d if Array(rules["high"]).any? { |keyword| normalized.include?(keyword.to_s.downcase) }
        return 1.15.to_d if Array(rules["medium"]).any? { |keyword| normalized.include?(keyword.to_s.downcase) }
        return 0.75.to_d if Array(rules["low"]).any? { |keyword| normalized.include?(keyword.to_s.downcase) }

        1.0.to_d
      end

      def asset_match_score_for(target)
        matched = matching_activity_count(target)
        return 0.2.to_d if matched.zero?

        [ matched.to_d / 5, 1.0.to_d ].min
      end

      def ga4_engagement_score
        return 0.to_d if recent_metrics.empty?

        recent_metrics.sum(&:engagement_score).to_d / recent_metrics.size
      end

      def work_cost_for(target_type)
        rules = profile.work_cost_rules.to_h
        minutes = case target_type
        when "traffic_entry" then rules["title_meta"]
        when "conversion_path" then rules["cta"]
        when "asset" then rules["supply_addition"]
        else rules["article"] || rules["title_meta"]
        end
        (minutes.to_d / 60).round(2)
      end

      def expected_value_for(demand:, supply:, intent:, asset_match:, engagement:)
        shortage_boost = supply.to_d <= 0 ? 1.5.to_d : [ 1.8.to_d - (supply.to_d / 100), 0.7.to_d ].max
        ctr_boost = ctr < 0.02.to_d && impressions.positive? ? 1.35.to_d : 1.0.to_d
        rank_boost = average_position.between?(8, 20) ? 1.3.to_d : 1.0.to_d
        engagement_boost = engagement.to_d < 15 && traffic.positive? ? 1.2.to_d : 1.0.to_d
        asset_gap_boost = asset_match.to_d < 0.4.to_d ? 1.25.to_d : 1.0.to_d

        (demand.to_d * 45 * intent.to_d * shortage_boost * ctr_boost * rank_boost * engagement_boost * asset_gap_boost).round
      end

      def latest_page_for(query)
        latest_gsc_imports.lazy.filter_map { |data_import| page_from_gsc_import(data_import, query) }.first
      end

      def query_target_type(query)
        classification = query_classification_for(query)
        return "comparison_query" if classification.include?("comparison")
        return "conversion_query" if classification.include?("conversion")

        "query"
      end

      def query_classification_for(text)
        normalized = text.to_s.downcase
        profile.query_classification_rules.to_h.filter_map do |label, keywords|
          label if Array(keywords).any? { |keyword| normalized.include?(keyword.to_s.downcase) }
        end
      end

      def evidence_sources(source)
        case source
        when "query" then %w[gsc business_db]
        when "ga4_aggregate" then %w[ga4 business_db]
        else %w[business_db activity]
        end
      end

      def latest_gsc_imports
        @latest_gsc_imports ||= business.data_sources
          .where(source_type: "gsc")
          .includes(:data_imports)
          .flat_map { |source| source.data_imports.recent.limit(3).to_a }
          .sort_by { |data_import| [ data_import.imported_at || Time.zone.at(0), data_import.created_at || Time.zone.at(0) ] }
          .reverse
          .first(3)
      end

      def queries_from_gsc_import(data_import)
        rows_from_gsc_import(data_import).filter_map { |row| row[:query] }
      end

      def page_from_gsc_import(data_import, query)
        rows_from_gsc_import(data_import).find { |row| row[:query] == query }&.dig(:page)
      end

      def rows_from_gsc_import(data_import)
        rows = rows_from_gsc_processed_text(data_import.processed_text)
        rows.presence || rows_from_gsc_raw_text(data_import.raw_text)
      end

      def rows_from_gsc_processed_text(processed_text)
        return [] if processed_text.blank?

        CSV.parse(processed_text, headers: true).filter_map do |row|
          query = row["query"].presence || row["検索クエリ"].presence || row["keyword"].presence
          next if query.blank?

          { query:, page: row["page"].presence || row["ページ"].presence || row["url"].presence }
        end
      rescue CSV::MalformedCSVError
        []
      end

      def rows_from_gsc_raw_text(raw_text)
        return [] if raw_text.blank?

        parsed = JSON.parse(raw_text)
        Array(parsed["rows"]).filter_map do |row|
          query = Array(row["keys"]).first.presence || row["query"].presence
          next if query.blank?

          { query:, page: row["page"].presence || row["url"].presence }
        end
      rescue JSON::ParserError
        []
      end
    end
  end
end

module Aicoo
  module Lovable
    class LandingPageAnalyticsReader
      Result = Data.define(:ga4, :gsc)

      def self.latest_snapshots_for(business)
        %w[ga4 gsc].index_with do |source_type|
          import_ids = business.data_sources.where(source_type:).joins(:data_imports).pluck("data_imports.id")
          AicooDataSnapshot
            .where(source_type:, source_id: import_ids)
            .where("COALESCE(payload ->> 'snapshot_status', 'active') NOT IN (?)", %w[archived ignored])
            .recent
            .first
        end
      end

      def initialize(business:, generation_run: nil, landing_page: nil, started_at:, ended_at:, target_paths: nil, snapshots: nil)
        @business = business
        @generation_run = generation_run
        @landing_page = landing_page
        @started_at = started_at
        @ended_at = ended_at
        @provided_target_paths = target_paths
        @provided_snapshots = snapshots&.stringify_keys
      end

      def call
        return Result.new(ga4: unavailable("ga4"), gsc: unavailable("gsc")) unless started_at

        Result.new(ga4: ga4_metrics, gsc: gsc_metrics)
      end

      private

      attr_reader :business, :generation_run, :landing_page, :started_at, :ended_at, :provided_target_paths, :provided_snapshots

      def ga4_metrics
        rows = matching_rows("ga4")
        return unavailable("ga4") if rows.empty?

        sessions = rows.sum { |row| decimal(value(row, "sessions", metric_index: 2)) }
        engagement_total = rows.sum do |row|
          decimal(value(row, "userEngagementDuration", "engagement_seconds", "averageEngagementTime", "average_engagement_time_seconds", metric_index: 4))
        end
        bounce_values = rows.filter_map { |row| optional_decimal(value(row, "bounceRate", "bounce_rate")) }
        {
          "available" => true,
          "pageviews" => rows.sum { |row| decimal(value(row, "screenPageViews", "pageviews", "page_views", "views", metric_index: 0)) }.to_i,
          "active_users" => rows.sum { |row| decimal(value(row, "activeUsers", "active_users", "users", metric_index: 1)) }.to_i,
          "sessions" => sessions.to_i,
          "engagement_seconds" => sessions.positive? ? (engagement_total / sessions).round(2).to_f : nil,
          "event_count" => rows.sum { |row| decimal(value(row, "eventCount", "event_count", metric_index: 3)) }.to_i,
          "conversions" => rows.sum { |row| decimal(value(row, "keyEvents", "conversions", "conversion_count")) }.to_i,
          "cta_clicks" => rows.sum { |row| decimal(value(row, "ctaClicks", "cta_clicks", "cta_click_count")) }.to_i,
          "landing_page_views" => rows.sum { |row| decimal(value(row, "landingPageViews", "landing_page_views")) }.to_i,
          "bounce_rate" => average(bounce_values),
          "page_paths" => rows.map { |row| page_value(row) }.uniq.first(20),
          "source" => "aicoo_data_snapshot",
          "source_id" => latest_snapshot("ga4")&.id,
          "scope" => "landing_page"
        }
      end

      def gsc_metrics
        source_rows = matching_rows("gsc")
        return unavailable("gsc") if source_rows.empty?

        rows = gsc_daily_rows(source_rows)

        impressions = rows.sum { |row| decimal(value(row, "impressions")) }
        clicks = rows.sum { |row| decimal(value(row, "clicks")) }
        weighted_position = rows.sum do |row|
          decimal(value(row, "position", "average_position")) * decimal(value(row, "impressions"))
        end
        {
          "available" => true,
          "impressions" => impressions.to_i,
          "clicks" => clicks.to_i,
          "ctr" => impressions.positive? ? (clicks / impressions).round(4).to_f : 0.0,
          "average_position" => impressions.positive? ? (weighted_position / impressions).round(2).to_f : nil,
          "page_paths" => rows.map { |row| page_value(row) }.uniq.first(20),
          "source" => "aicoo_data_snapshot",
          "source_id" => latest_snapshot("gsc")&.id,
          "scope" => "landing_page"
        }
      end

      def gsc_daily_rows(rows)
        rows.group_by { |row| first_present(row["date"], row["recorded_on"], "unknown_date").to_s }.map do |_date, date_rows|
          page_only = date_rows.reject { |row| query_value(row).present? }
          next page_only.max_by { |row| decimal(value(row, "impressions")) } if page_only.any?

          impressions = date_rows.sum { |row| decimal(value(row, "impressions")) }
          clicks = date_rows.sum { |row| decimal(value(row, "clicks")) }
          weighted_position = date_rows.sum do |row|
            decimal(value(row, "position", "average_position")) * decimal(value(row, "impressions"))
          end
          {
            "impressions" => impressions,
            "clicks" => clicks,
            "position" => impressions.positive? ? weighted_position / impressions : 0
          }
        end
      end

      def query_value(row)
        first_present(
          row["query"],
          row["keyword"],
          Array(row["keys"]).find { |candidate| candidate.present? && !candidate.to_s.start_with?("/") && !candidate.to_s.match?(%r{\Ahttps?://}i) }
        )
      end

      def matching_rows(source_type)
        rows_for(source_type).select do |row|
          path = normalize(page_value(row))
          path.present? && target_paths.include?(path) && in_measurement_window?(row)
        end
      end

      def rows_for(source_type)
        snapshot = latest_snapshot(source_type)
        return [] unless snapshot

        payload = snapshot.payload.to_h.deep_stringify_keys
        Array(payload["rows"] || payload.dig("metrics", "rows")).map { |row| row.to_h.deep_stringify_keys }
      end

      def latest_snapshot(source_type)
        return provided_snapshots[source_type] if provided_snapshots&.key?(source_type)

        @latest_snapshots ||= {}
        return @latest_snapshots[source_type] if @latest_snapshots.key?(source_type)

        import_ids = business.data_sources.where(source_type:).joins(:data_imports).pluck("data_imports.id")
        @latest_snapshots[source_type] = AicooDataSnapshot
          .where(source_type:, source_id: import_ids)
          .where("COALESCE(payload ->> 'snapshot_status', 'active') NOT IN (?)", %w[archived ignored])
          .recent
          .first
      end

      def target_paths
        @target_paths ||= Array(provided_target_paths).presence&.filter_map { |value| normalize(value) }&.uniq || [
          generation_run.metadata.to_h.dig("publication", "production_url"),
          landing_page.published_slug.present? ? "/lp/#{landing_page.published_slug}" : nil,
          generation_run.metadata.to_h["page_path"],
          generation_run.metadata.to_h["target_url"]
        ].filter_map { |value| normalize(value) }.uniq
      end

      def page_value(row)
        first_present(
          row["page"],
          row["pagePath"],
          row["page_path"],
          row["landingPage"],
          row["landing_page"],
          row["pageLocation"],
          row["page_location"],
          row["url"],
          Array(row["keys"]).find { |candidate| candidate.to_s.start_with?("/") || candidate.to_s.match?(%r{\Ahttps?://}i) },
          dimension_path(row)
        )
      end

      def dimension_path(row)
        Array(row["dimensionValues"]).filter_map { |item| item.to_h["value"].presence || item.to_s.presence }.find do |candidate|
          candidate.start_with?("/") || candidate.match?(%r{\Ahttps?://}i)
        end
      end

      def in_measurement_window?(row)
        raw = first_present(row["date"], row["recorded_on"], row["start_date"])
        return true if raw.blank?

        date = Date.parse(raw.to_s)
        date >= started_at.to_date && date <= ended_at.to_date
      rescue ArgumentError
        true
      end

      def value(row, *keys, metric_index: nil)
        keys.each { |key| return row[key] if row[key].present? }
        return unless metric_index

        Array(row["metricValues"])[metric_index].to_h["value"]
      end

      def normalize(value)
        Aicoo::UrlNormalizer.call(value)
      rescue StandardError
        nil
      end

      def decimal(value)
        BigDecimal(value.to_s.presence || "0")
      rescue ArgumentError
        0.to_d
      end

      def optional_decimal(value)
        return if value.blank?

        decimal(value)
      end

      def average(values)
        return if values.empty?

        (values.sum / values.length).round(4).to_f
      end

      def first_present(*values)
        values.flatten.compact_blank.first
      end

      def unavailable(source_type)
        {
          "available" => false,
          "source" => "aicoo_data_snapshot",
          "source_id" => latest_snapshot(source_type)&.id,
          "scope" => "landing_page",
          "missing_reason" => target_paths.empty? ? "production_url_missing" : "matching_page_rows_missing"
        }
      end
    end
  end
end

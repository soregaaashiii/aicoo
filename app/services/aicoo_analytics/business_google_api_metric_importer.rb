module AicooAnalytics
  class BusinessGoogleApiMetricImporter
    Result = Data.define(:business, :start_date, :end_date, :metrics, :source_results, :credential_snapshots) do
      def metric_count
        metrics.size
      end

      def imported_source_labels
        source_results.select { |row| row.fetch(:status) == "success" }.map { |row| row.fetch(:source).upcase }
      end
    end

    class Error < StandardError; end

    GA4_METRICS = %w[
      sessions
      activeUsers
      screenPageViews
      averageEngagementTime
      engagementRate
      conversions
      eventCount
    ].freeze

    def initialize(business:, today: Date.current, days: nil, source_types: %w[gsc ga4], gsc_client: nil, ga4_client: nil)
      @business = business
      @today = today.to_date
      @days = days
      @source_types = source_types
      @gsc_client = gsc_client
      @ga4_client = ga4_client
    end

    def call
      gsc_setting = source_enabled?("gsc") ? analytics_setting("gsc") : nil
      ga4_setting = source_enabled?("ga4") ? analytics_setting("ga4") : nil
      raise Error, "GSC site_url または GA4 property_id が未設定です。" unless gsc_setting || ga4_setting

      source_results = []
      credential_snapshots = {
        "gsc" => google_credential_snapshot(gsc_setting),
        "ga4" => google_credential_snapshot(ga4_setting)
      }.compact
      gsc_values = fetch_gsc(gsc_setting, source_results) if gsc_setting
      ga4_values = fetch_ga4(ga4_setting, source_results) if ga4_setting
      metrics = save_metrics(gsc_values || {}, ga4_values || {})

      Result.new(business:, start_date:, end_date:, metrics:, source_results:, credential_snapshots:)
    end

    private

    attr_reader :business, :today, :days, :source_types, :gsc_client, :ga4_client

    def source_enabled?(source_type)
      source_types.map(&:to_s).include?(source_type)
    end

    def fetch_gsc(setting, source_results)
      with_fetch_run(setting, "gsc", source_results) do
        response = resolved_gsc_client(setting).query(
          site_url: setting.site_url,
          start_date:,
          end_date:,
          dimensions: %w[date],
          row_limit: 25_000
        )
        aggregate_gsc_rows(response.fetch("rows", []))
      end
    end

    def fetch_ga4(setting, source_results)
      with_fetch_run(setting, "ga4", source_results) do
        response = resolved_ga4_client(setting).run_report(
          property_id: setting.property_id,
          start_date:,
          end_date:,
          dimensions: %w[date],
          metrics: GA4_METRICS,
          limit: 10_000
        )
        aggregate_ga4_rows(response.fetch("rows", []))
      end
    end

    def with_fetch_run(setting, source_type, source_results)
      run = setting.analytics_fetch_runs.create!(status: "running", source_type:, started_at: Time.current)
      values = yield
      setting.update!(last_fetched_at: Time.current)
      run.update!(
        status: "success",
        finished_at: Time.current,
        snapshot_count: 0,
        updated_neglect_loss_count: 0,
        error_message: nil
      )
      source_results << { source: source_type, status: "success", row_count: values.size, run_id: run.id }
      values
    rescue StandardError => e
      run&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
      source_results << { source: source_type, status: "failed", error_message: e.message, run_id: run&.id }
      raise
    end

    def save_metrics(gsc_values, ga4_values)
      (gsc_values.keys | ga4_values.keys).sort.map do |date|
        metric = BusinessMetricDaily.find_or_initialize_by(business:, recorded_on: date)
        metric.assign_attributes(gsc_values.fetch(date, {})) if gsc_values.key?(date)
        metric.assign_attributes(ga4_values.fetch(date, {})) if ga4_values.key?(date)
        metric.save!
        metric
      end
    end

    def aggregate_gsc_rows(rows)
      rows.each_with_object({}) do |row, totals|
        date = date_from_key(row.dig("keys", 0))
        next unless date

        current = totals[date] ||= { clicks: 0, impressions: 0, weighted_position: 0.to_d }
        impressions = numeric(row["impressions"])
        current[:clicks] += numeric(row["clicks"])
        current[:impressions] += impressions
        current[:weighted_position] += row["position"].to_d * impressions
      end.transform_values do |values|
        {
          clicks: values.fetch(:clicks),
          impressions: values.fetch(:impressions),
          average_position: average_position(values)
        }
      end
    end

    def aggregate_ga4_rows(rows)
      rows.each_with_object({}) do |row, totals|
        date = date_from_key(row.dig("dimensionValues", 0, "value"))
        next unless date

        values = row.fetch("metricValues", []).map { |metric| metric["value"] }
        current = totals[date] ||= {
          sessions: 0,
          users: 0,
          pageviews: 0,
          average_engagement_time_weighted: 0.to_d,
          engagement_rate_weighted: 0.to_d,
          conversions: 0,
          event_count: 0
        }
        sessions = numeric(values[0])
        current[:sessions] += sessions
        current[:users] += numeric(values[1])
        current[:pageviews] += numeric(values[2])
        current[:average_engagement_time_weighted] += values[3].to_d * sessions
        current[:engagement_rate_weighted] += values[4].to_d * sessions
        current[:conversions] += numeric(values[5])
        current[:event_count] += numeric(values[6])
      end.transform_values do |values|
        {
          sessions: values.fetch(:sessions),
          users: values.fetch(:users),
          pageviews: values.fetch(:pageviews),
          average_engagement_time_seconds: weighted_average(values, :average_engagement_time_weighted).round,
          engagement_rate: weighted_average(values, :engagement_rate_weighted),
          conversions: values.fetch(:conversions),
          event_count: values.fetch(:event_count)
        }
      end
    end

    def weighted_average(values, key)
      sessions = values.fetch(:sessions)
      return 0 if sessions.zero?

      (values.fetch(key) / sessions).round(4)
    end

    def average_position(values)
      impressions = values.fetch(:impressions)
      return 0 if impressions.zero?

      (values.fetch(:weighted_position) / impressions).round(2)
    end

    def analytics_setting(source_type)
      existing_analytics_setting(source_type) || build_analytics_setting(source_type)
    end

    def existing_analytics_setting(source_type)
      site = AicooAnalyticsSite.where(business:).recent.first
      setting = source_type == "gsc" ? site&.gsc_setting : site&.ga4_setting
      return setting if setting&.enabled?

      identifier = analytics_identifier(source_type)
      return nil if identifier.blank?

      scope = AnalyticsSourceSetting.where(source_type:, enabled: true)
      source_type == "gsc" ? scope.find_by(site_url: identifier) : scope.find_by(property_id: identifier)
    end

    def build_analytics_setting(source_type)
      identifier = analytics_identifier(source_type)
      return nil if identifier.blank?

      attributes = {
        source_type:,
        name: "#{business.name} #{source_type.upcase}",
        enabled: true,
        authentication_mode: "shared",
        google_credential: AicooGoogleCredential.default
      }
      attributes[source_type == "gsc" ? :site_url : :property_id] = identifier
      AnalyticsSourceSetting.create!(attributes)
    end

    def analytics_identifier(source_type)
      setting = BusinessDataSourceSetting.find_by(business:, source_key: source_type)
      case source_type
      when "gsc"
        setting&.connection_field_value("site_url").presence ||
          setting&.property_identifier.presence ||
          business.gsc_site_url.presence
      when "ga4"
        setting&.connection_field_value("property_id").presence ||
          setting&.property_identifier.presence ||
          AicooAnalyticsSite.where(business:).where.not(ga4_property_id: [ nil, "" ]).recent.first&.ga4_property_id
      end
    end

    def resolved_gsc_client(setting)
      gsc_client || GscSearchAnalyticsClient.new(oauth_client: token_client(setting))
    end

    def resolved_ga4_client(setting)
      ga4_client || Ga4DataApiClient.new(access_token: GoogleAccessToken.new(setting).call)
    end

    def token_client(setting)
      Struct.new(:setting) do
        def access_token
          AicooAnalytics::GoogleAccessToken.new(setting).call
        end
      end.new(setting)
    end

    def google_credential_snapshot(setting)
      return if setting.blank?

      credential = setting.effective_google_credential || AicooGoogleCredential.default
      credential&.reload&.diagnostic_snapshot
    end

    def start_date
      end_date - (fetch_days - 1).days
    end

    def end_date
      today - 1.day
    end

    def fetch_days
      (days || 28).to_i
    end

    def date_from_key(value)
      return if value.blank?

      text = value.to_s
      return Date.strptime(text, "%Y%m%d") if text.match?(/\A\d{8}\z/)

      Date.iso8601(text)
    rescue Date::Error
      nil
    end

    def numeric(value)
      value.to_f.round
    end
  end
end

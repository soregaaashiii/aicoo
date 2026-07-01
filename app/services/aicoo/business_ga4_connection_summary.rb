module Aicoo
  class BusinessGa4ConnectionSummary
    Summary = Data.define(
      :connected,
      :configured,
      :property_id,
      :setting,
      :latest_run,
      :latest_success_run,
      :last_fetched_at,
      :last_count,
      :last_error
    )

    def initialize(business, health: nil)
      @business = business
      @health = health
    end

    def call
      Summary.new(
        connected: health&.ga4&.connected || false,
        configured: property_id.present?,
        property_id:,
        setting:,
        latest_run:,
        latest_success_run:,
        last_fetched_at: latest_run&.finished_at || latest_run&.started_at || setting&.last_fetched_at,
        last_count: latest_run&.snapshot_count.to_i,
        last_error: latest_failed_run&.error_message
      )
    end

    private

    attr_reader :business, :health

    def property_id
      @property_id ||= configured_property_id.presence || setting&.property_id.presence
    end

    def configured_property_id
      @configured_property_id ||= business_data_source_property_id.presence ||
                                   analytics_site&.ga4_property_id.presence ||
                                   named_setting&.property_id.presence
    end

    def business_data_source_property_id
      source_setting = BusinessDataSourceSetting.find_by(business:, source_key: "ga4")
      return unless source_setting&.enabled?

      source_setting.connection_field_value("property_id").presence || source_setting.property_identifier.presence
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
    end

    def setting
      identifier = configured_property_id
      @setting ||= AnalyticsSourceSetting.includes(:aicoo_analytics_site)
        .where(source_type: "ga4", enabled: true)
        .find do |row|
          row.aicoo_analytics_site&.business_id == business.id ||
            (identifier.present? && row.property_id == identifier) ||
            row.id == named_setting&.id
        end
    end

    def named_setting
      @named_setting ||= AnalyticsSourceSetting
        .where(source_type: "ga4", enabled: true)
        .to_a
        .find { |row| row.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i) }
    end

    def latest_run
      @latest_run ||= setting&.analytics_fetch_runs&.recent&.first
    end

    def latest_success_run
      @latest_success_run ||= setting&.analytics_fetch_runs&.where(status: "success")&.recent&.first
    end

    def latest_failed_run
      @latest_failed_run ||= setting&.analytics_fetch_runs&.where(status: "failed")&.recent&.first
    end
  end
end

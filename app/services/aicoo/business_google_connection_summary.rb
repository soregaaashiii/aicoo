module Aicoo
  class BusinessGoogleConnectionSummary
    Summary = Data.define(
      :source_key,
      :label,
      :connected,
      :configured,
      :enabled,
      :identifier,
      :credential,
      :setting,
      :latest_run,
      :latest_success_run,
      :last_fetched_at,
      :last_count,
      :last_error,
      :setting_source,
      :reauthentication_required,
      :status_label
    )

    SOURCE_LABELS = {
      "ga4" => "GA4",
      "gsc" => "GSC"
    }.freeze

    def initialize(business, source_key:, health: nil)
      @business = business
      @source_key = source_key.to_s
      @health = health
    end

    def call
      Summary.new(
        source_key:,
        label: SOURCE_LABELS.fetch(source_key),
        connected: connected?,
        configured: identifier.present?,
        enabled: business_data_source_setting.nil? || business_data_source_setting.enabled?,
        identifier:,
        credential:,
        setting:,
        latest_run:,
        latest_success_run:,
        last_fetched_at: latest_run&.finished_at || latest_run&.started_at || setting&.last_fetched_at,
        last_count: latest_run&.snapshot_count.to_i,
        last_error: latest_failed_run&.error_message,
        setting_source:,
        reauthentication_required: reauthentication_required?,
        status_label:
      )
    end

    private

    attr_reader :business, :source_key, :health

    def connected?
      source_health&.connected || credential&.connected? || false
    end

    def status_label
      return "無効" unless business_data_source_setting.nil? || business_data_source_setting.enabled?
      return "未設定" if identifier.blank?
      return "Google Credential未設定" if business_data_source_identifier.present? && credential.blank?
      return "再認証が必要" if reauthentication_required?
      return "最終取得失敗" if latest_run&.status == "failed"
      return "接続済み" if connected?

      "設定済み"
    end

    def source_health
      return unless health

      source_key == "ga4" ? health.ga4 : health.gsc
    end

    def identifier
      @identifier ||= business_data_source_identifier.presence ||
                      analytics_site_identifier.presence ||
                      named_setting_identifier.presence ||
                      business_gsc_site_url
    end

    def business_gsc_site_url
      business.gsc_site_url.presence if source_key == "gsc"
    end

    def setting_source
      return "BusinessDataSourceSetting" if business_data_source_identifier.present?
      return "AicooAnalyticsSite" if analytics_site_identifier.present?
      return "AnalyticsSourceSetting" if named_setting_identifier.present?
      return "Business#gsc_site_url" if business_gsc_site_url.present?

      "missing"
    end

    def reauthentication_required?
      latest_failed_run&.error_message.to_s.match?(/invalid_grant|expired or revoked/i).present? ||
        credential&.reauthentication_required? ||
        credential&.token_expired? ||
        credential.blank?
    end

    def business_data_source_identifier
      key = source_key == "ga4" ? "property_id" : "site_url"
      return unless business_data_source_setting&.enabled?

      business_data_source_setting.connection_field_value(key).presence ||
        business_data_source_setting.property_identifier.presence
    end

    def analytics_site_identifier
      source_key == "ga4" ? analytics_site&.ga4_property_id : analytics_site&.gsc_site_url
    end

    def named_setting_identifier
      source_key == "ga4" ? named_setting&.property_id : named_setting&.site_url
    end

    def credential
      explicit_id = business_data_source_setting&.metadata.to_h.dig("google_credential_id")
      explicit_credential = AicooGoogleCredential.find_by(id: explicit_id) if explicit_id.present?
      return explicit_credential if explicit_credential
      return nil if business_data_source_identifier.present?

      setting&.google_credential || AicooGoogleCredential.default
    end

    def business_data_source_setting
      @business_data_source_setting ||= BusinessDataSourceSetting.find_by(business:, source_key:)
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
    end

    def setting
      @setting ||= AnalyticsSourceSetting.includes(:aicoo_analytics_site)
        .where(source_type: source_key, enabled: true)
        .find do |row|
          row.aicoo_analytics_site&.business_id == business.id ||
            identifier_matches?(row) ||
            row.id == named_setting&.id
        end
    end

    def named_setting
      @named_setting ||= AnalyticsSourceSetting
        .where(source_type: source_key, enabled: true)
        .to_a
        .find { |row| row.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i) }
    end

    def identifier_matches?(row)
      return false if identifier.blank?

      source_key == "ga4" ? row.property_id == identifier : row.site_url == identifier
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

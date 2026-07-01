module Aicoo
  class BusinessGoogleDebugSummary
    def initialize(business, source_key: "ga4")
      @business = business
      @source_key = source_key.to_s
    end

    def call
      {
        business: business.slice(:id, :name, :gsc_site_url),
        source_key:,
        effective: {
          property_or_site: connection_summary.identifier,
          setting_source: connection_summary.setting_source,
          analytics_source_setting_id: connection_summary.setting&.id,
          google_credential_id: connection_summary.credential&.id,
          google_credential_name: connection_summary.credential&.name,
          google_account_email: connection_summary.credential&.google_account_email,
          reauthentication_required: connection_summary.reauthentication_required,
          status_label: connection_summary.status_label
        },
        business_data_source_setting: business_data_source_setting&.attributes,
        business_data_source_metadata: business_data_source_setting&.metadata,
        analytics_site: analytics_site&.attributes,
        analytics_source_setting: connection_summary.setting&.attributes,
        google_credential: credential_snapshot,
        latest_fetch_run: latest_fetch_run&.attributes
      }
    end

    private

    attr_reader :business, :source_key

    def connection_summary
      @connection_summary ||= BusinessGoogleConnectionSummary.new(business, source_key:).call
    end

    def business_data_source_setting
      @business_data_source_setting ||= BusinessDataSourceSetting.find_by(business:, source_key:)
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
    end

    def latest_fetch_run
      connection_summary.latest_run
    end

    def credential_snapshot
      credential = connection_summary.credential
      return unless credential

      credential.diagnostic_snapshot.merge(
        "connected" => credential.connected?,
        "reauthentication_required" => credential.reauthentication_required?,
        "token_expired" => credential.token_expired?
      )
    end
  end
end

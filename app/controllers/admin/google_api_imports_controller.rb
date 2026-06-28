module Admin
  class GoogleApiImportsController < ApplicationController
    def index
      @businesses = Business.includes(:business_data_source_settings).order(:name)
      @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
      @business_analytics_summaries = Aicoo::BusinessAnalyticsSummary.for_businesses(
        @businesses,
        health_result: @business_integration_health
      )
    end

    def create
      business = Business.find(params.expect(:business_id))
      result = AicooAnalytics::BusinessGoogleApiMetricImporter.new(business:).call
      sources = result.imported_source_labels.presence || [ "Google API" ]
      redirect_to admin_google_api_imports_path,
                  notice: "#{business.name}: #{sources.join(' / ')} から直接取得しました。BusinessMetricDaily #{result.metric_count}日分を更新しました。"
    rescue AicooAnalytics::BusinessGoogleApiMetricImporter::Error,
           GoogleOauthClient::MissingCredentialsError,
           GoogleOauthClient::Error,
           GscSearchAnalyticsClient::Error,
           AicooAnalytics::Ga4DataApiClient::Error => e
      redirect_to admin_google_api_imports_path, alert: "Google APIから取得できませんでした: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_google_api_imports_path, alert: "Google APIから取得できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end
  end
end

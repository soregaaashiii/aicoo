module AicooAnalytics
  class DailyFetchJob < ApplicationJob
    queue_as :default

    def perform
      successful_settings = []
      AnalyticsSourceSetting.where(enabled: true).includes(aicoo_analytics_site: :business).find_each do |setting|
        run = FetchRunner.new(setting).call
        successful_settings << setting if run.respond_to?(:status) && run.status == "success"
      end

      refresh_business_metrics(successful_settings)
    end

    private

    def refresh_business_metrics(settings)
      settings.group_by { |setting| setting.aicoo_analytics_site&.business }.each do |business, business_settings|
        next unless business

        BusinessGoogleApiMetricImporter.new(
          business:,
          days: business_settings.filter_map(&:fetch_days).max,
          source_types: business_settings.map(&:source_type).uniq
        ).call
      rescue StandardError => e
        Rails.logger.error(
          "[AicooAnalytics::DailyFetchJob] BusinessMetricDaily refresh failed " \
          "business_id=#{business.id} error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end

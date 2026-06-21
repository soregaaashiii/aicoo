module AicooAnalytics
  class DailyFetchJob < ApplicationJob
    queue_as :default

    def perform
      AnalyticsSourceSetting.where(enabled: true).find_each do |setting|
        FetchRunner.new(setting).call
      end
    end
  end
end

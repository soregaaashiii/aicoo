module AicooAnalytics
  class BusinessGoogleApiImportJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = GoogleApiImportRun.find(run_id)
      return unless run.running?

      run.mark_running!
      result = BusinessGoogleApiMetricImporter.new(
        business: run.business,
        days: run.fetched_days,
        source_types: run.source_types.presence || %w[gsc ga4]
      ).call
      run.mark_success!(result)
    rescue StandardError => e
      run&.mark_failed!(e)
      Rails.logger.error("[BusinessGoogleApiImportJob] run_id=#{run_id} failed: #{e.class}: #{e.message}")
    end
  end
end

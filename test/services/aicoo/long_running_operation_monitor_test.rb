require "test_helper"

module Aicoo
  class LongRunningOperationMonitorTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      GoogleApiImportRun.delete_all
    end

    test "returns running completed and failed operations" do
      running = GoogleApiImportRun.create!(
        business: @business,
        status: "running",
        source_types: %w[gsc ga4],
        fetched_days: 3,
        started_at: 5.minutes.ago
      )
      success = GoogleApiImportRun.create!(
        business: @business,
        status: "success",
        source_types: %w[gsc],
        fetched_days: 1,
        started_at: 20.minutes.ago,
        finished_at: 19.minutes.ago,
        duration_seconds: 60,
        updated_metric_count: 4
      )
      failed = GoogleApiImportRun.create!(
        business: @business,
        status: "failed",
        source_types: %w[ga4],
        fetched_days: 1,
        started_at: 30.minutes.ago,
        finished_at: 29.minutes.ago,
        error_message: "GA4 Property IDが未設定です"
      )

      result = LongRunningOperationMonitor.new.call

      running_operation = result.running_operations.find { |operation| operation.key == "google-api-#{running.id}" }
      success_operation = result.recent_operations.find { |operation| operation.key == "google-api-#{success.id}" }
      failed_operation = result.recent_operations.find { |operation| operation.key == "google-api-#{failed.id}" }

      assert result.running?
      assert_equal "実行中", running_operation.status_label
      assert_equal "完了", success_operation.status_label
      assert_equal "失敗", failed_operation.status_label
      assert_equal "GA4 Property IDが未設定です", failed_operation.error_message
    end
  end
end

require "test_helper"

module Admin
  class ExecutionRunsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @business = businesses(:suelog)
      GoogleApiImportRun.delete_all
      @run = GoogleApiImportRun.create!(
        business: @business,
        status: "failed",
        source_types: %w[ga4],
        fetched_days: 1,
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        duration_seconds: 60,
        updated_metric_count: 0,
        error_message: "GA4 metric名が無効です\nFull raw Google API error payload"
      )
    end

    test "index shows execution results as compact rows" do
      get admin_execution_runs_url

      assert_response :success
      assert_includes response.body, "実行結果一覧"
      assert_includes response.body, "operation-row operation-row-failed"
      assert_includes response.body, "GA4 metric名が無効です"
      assert_not_includes response.body, "Full raw Google API error payload"
      assert_includes response.body, admin_execution_run_path("google-api-#{@run.id}")
    end

    test "show displays full error details" do
      get admin_execution_run_url("google-api-#{@run.id}")

      assert_response :success
      assert_includes response.body, "実行履歴詳細"
      assert_includes response.body, "GA4 metric名が無効です"
      assert_includes response.body, "Full raw Google API error payload"
    end
  end
end

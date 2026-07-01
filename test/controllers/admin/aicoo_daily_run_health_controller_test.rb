require "test_helper"

module Admin
  class AicooDailyRunHealthControllerTest < ActionDispatch::IntegrationTest
    test "shows daily run health in manual mode" do
      with_env("AICOO_DAILY_RUN_ENABLED", nil) do
        get admin_aicoo_daily_run_health_url
      end

      assert_response :success
      assert_includes response.body, "Daily Run Health"
      assert_includes response.body, "Daily Run Mode"
      assert_includes response.body, "Manual"
      assert_includes response.body, "AICOO_DAILY_RUN_ENABLED"
    end

    test "shows cron ready when env is enabled" do
      with_env("AICOO_DAILY_RUN_ENABLED", "true") do
        get admin_aicoo_daily_run_health_url
      end

      assert_response :success
      assert_includes response.body, "Cron Ready"
      assert_includes response.body, "CronからDaily Runを安全に起動できます"
    end

    test "shows cron health dashboard with latest run steps and history" do
      daily_run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "cron",
        started_at: 5.minutes.ago,
        finished_at: 3.minutes.ago,
        retry_count: 2,
        error_message: "Google API error"
      )
      daily_run.aicoo_daily_run_steps.create!(
        step_name: "analytics_fetch",
        status: "failed",
        started_at: 5.minutes.ago,
        finished_at: 4.minutes.ago,
        duration_seconds: 60,
        error_message: "Google API error"
      )

      with_env("AICOO_DAILY_RUN_ENABLED", "true") do
        get admin_cron_health_url
      end

      assert_response :success
      assert_includes response.body, "異常検知"
      assert_includes response.body, "最新Run"
      assert_includes response.body, "Step一覧"
      assert_includes response.body, "過去30件のDaily Run"
      assert_includes response.body, "analytics_fetch"
      assert_includes response.body, "Google APIエラー"
      assert_includes response.body, "Render Cron"
      assert_includes response.body, aicoo_daily_run_path(daily_run)
    end

    private

    def with_env(key, value)
      previous = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
      yield
    ensure
      previous.nil? ? ENV.delete(key) : ENV[key] = previous
    end
  end
end

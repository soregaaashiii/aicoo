require "test_helper"

module Aicoo
  class CronHealthDashboardTest < ActiveSupport::TestCase
    test "summarizes latest cron run and step counts" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "success",
        source: "cron",
        started_at: 3.minutes.ago,
        finished_at: 1.minute.ago
      )
      run.aicoo_daily_run_steps.create!(step_name: "analytics_fetch", status: "success")
      run.aicoo_daily_run_steps.create!(step_name: "serp_fetch", status: "skipped", metadata: { warning: true, reason: "serp_optional_missing" })

      with_env("AICOO_DAILY_RUN_ENABLED", "true") do
        dashboard = Aicoo::CronHealthDashboard.new.call

        assert_equal run, dashboard.latest_run
        assert_equal run.started_at.to_i, dashboard.last_cron_started_at.to_i
        assert_equal 1, dashboard.today_run_count
        assert_equal 1, dashboard.today_success_count
        assert_equal "success", dashboard.status
        assert_equal "Daily Run 注意", dashboard.summary.title
        assert_equal 2, dashboard.latest_step_rows.size
        assert_equal 1, dashboard.history_rows.first.success_count
      end
    end

    test "detects stale running and api errors" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "running",
        source: "cron",
        started_at: 45.minutes.ago,
        retry_count: 2
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "analytics_fetch",
        status: "failed",
        error_message: "Google OAuth refresh token expired"
      )

      with_env("AICOO_DAILY_RUN_ENABLED", "true") do
        dashboard = Aicoo::CronHealthDashboard.new.call
        warning_keys = dashboard.warnings.map(&:key)

        assert_includes warning_keys, :stale_running
        assert_includes warning_keys, :retrying
        assert_includes warning_keys, :google_error
        assert_equal "critical", dashboard.summary.severity
      end
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

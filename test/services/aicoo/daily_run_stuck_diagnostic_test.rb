require "test_helper"

module Aicoo
  class DailyRunStuckDiagnosticTest < ActiveSupport::TestCase
    test "returns last successful started and running step details" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "stuck",
        source: "cron",
        started_at: 45.minutes.ago,
        finished_at: 5.minutes.ago,
        error_message: "stuck"
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "analytics_fetch",
        status: "success",
        started_at: 44.minutes.ago,
        finished_at: 40.minutes.ago
      )
      running = run.aicoo_daily_run_steps.create!(
        step_name: "action_generation",
        status: "running",
        started_at: 39.minutes.ago,
        metadata: { "heartbeat" => "2026-07-11T10:00:00+09:00" }
      )

      row = DailyRunStuckDiagnostic.call(limit: 1).first

      assert_equal run, row.run
      assert_equal "analytics_fetch", row.last_successful_step.step_name
      assert_equal running, row.last_started_step
      assert_equal running, row.last_running_step
      assert_equal "2026-07-11T10:00:00+09:00", row.heartbeat
      assert_equal "stuck", row.exception
    end
  end
end

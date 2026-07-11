require "test_helper"

module Aicoo
  class DailyRunStuckGuardTest < ActiveSupport::TestCase
    test "marks stale running run stuck first time" do
      run = create_running_run(step_name: "action_generation")

      result = DailyRunStuckGuard.call(threshold: 30.minutes)

      assert_equal 1, result.checked_count
      assert_equal 1, result.stuck_count
      assert_equal 0, result.partial_failed_count
      assert_equal "stuck", run.reload.status
      assert_match "last_step=action_generation", run.error_message
    end

    test "marks same step failed and run partial failed after repeated stucks" do
      2.times do
        stuck_run = AicooDailyRun.create!(
          target_date: Date.yesterday,
          status: "stuck",
          source: "cron",
          started_at: 2.hours.ago,
          finished_at: 90.minutes.ago
        )
        stuck_run.aicoo_daily_run_steps.create!(
          step_name: "action_generation",
          status: "running",
          started_at: 2.hours.ago
        )
      end

      run = create_running_run(step_name: "action_generation")
      step = run.current_step

      result = DailyRunStuckGuard.call(threshold: 30.minutes)

      assert_equal 1, result.checked_count
      assert_equal 0, result.stuck_count
      assert_equal 1, result.partial_failed_count
      assert_equal "partial_failed", run.reload.status
      assert_equal "failed", step.reload.status
      assert_match "同じStep(action_generation)", step.error_message
    end

    private

    def create_running_run(step_name:)
      run = AicooDailyRun.create!(
        target_date: Date.current,
        status: "running",
        source: "cron",
        started_at: 45.minutes.ago
      )
      run.aicoo_daily_run_steps.create!(
        step_name:,
        status: "running",
        started_at: 40.minutes.ago
      )
      run
    end
  end
end

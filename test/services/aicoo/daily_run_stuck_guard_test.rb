require "test_helper"

module Aicoo
  class DailyRunStuckGuardTest < ActiveSupport::TestCase
    test "marks stale running run stuck first time" do
      run = create_running_run(step_name: "action_generation")
      step = run.current_step

      result = DailyRunStuckGuard.call(threshold: 30.minutes)

      assert_equal 1, result.checked_count
      assert_equal 1, result.stuck_count
      assert_equal 0, result.partial_failed_count
      assert_equal "stuck", run.reload.status
      assert_equal "failed", step.reload.status
      assert step.finished_at.present?
      assert_equal true, step.metadata.fetch("orphaned")
      assert_equal "orphan_running_run", step.metadata.dig("stuck_guard", "reason")
      assert_match "last_step=action_generation", run.error_message
    end

    test "does not mark recently heartbeated running run stuck" do
      run = create_running_run(step_name: "action_generation")
      run.current_step.update!(
        metadata: {
          "heartbeat" => 2.minutes.ago.iso8601
        }
      )

      result = DailyRunStuckGuard.call(threshold: 30.minutes)

      assert_equal 0, result.checked_count
      assert_equal 0, result.stuck_count
      assert_equal "running", run.reload.status
      assert_equal "running", run.current_step.status
    end

    test "marks same step failed and run partial failed after repeated stucks" do
      2.times do
        stuck_run = AicooDailyRun.create!(
          target_date: Date.current,
          status: "stuck",
          source: "cron",
          started_at: 2.hours.ago,
          finished_at: 90.minutes.ago
        )
        stuck_run.aicoo_daily_run_steps.create!(
          step_name: "action_generation",
          status: "failed",
          started_at: 2.hours.ago,
          finished_at: 90.minutes.ago,
          metadata: {
            "stuck_guard" => {
              "reason" => "orphan_running_run"
            }
          }
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

    test "diagnoses orphan rows without updating records" do
      run = create_running_run(step_name: "insight_generation")

      rows = DailyRunStuckGuard.diagnose_orphans

      row = rows.find { |item| item.run == run }
      assert row.orphan
      assert_equal "insight_generation", row.step.step_name
      assert row.stale_minutes >= 30
      assert_equal "running", run.reload.status
    end

    test "repair orphan dry run does not update records" do
      run = create_running_run(step_name: "insight_generation")

      result = DailyRunStuckGuard.repair_orphan_runs!(apply: false)

      assert_equal 1, result.checked_count
      assert_equal 0, result.stuck_count
      assert_equal "running", run.reload.status
      assert_nil run.finished_at
    end

    test "repair orphan apply finishes stale running run" do
      run = create_running_run(step_name: "insight_generation")

      result = DailyRunStuckGuard.repair_orphan_runs!(apply: true)

      assert_equal 1, result.checked_count
      assert_equal 1, result.stuck_count
      assert_equal "stuck", run.reload.status
      assert run.finished_at.present?
      assert_equal "failed", run.current_step.status
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
      run.current_step.update_columns(updated_at: 40.minutes.ago)
      run.update_columns(updated_at: 45.minutes.ago)
      run
    end
  end
end

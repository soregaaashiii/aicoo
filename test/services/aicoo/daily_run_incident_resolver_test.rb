require "test_helper"

module Aicoo
  class DailyRunIncidentResolverTest < ActiveSupport::TestCase
    setup do
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
    end

    test "returns dynamic incidents grouped by step and root cause" do
      2.times do |index|
        create_run_with_step!(
          status: "stuck",
          step_name: "insight_generation",
          step_status: "failed",
          error_message: "OOM",
          started_at: (2 - index).hours.ago
        )
      end

      incidents = DailyRunIncidentResolver.call

      assert_equal 1, incidents.size
      assert_equal "insight_generation", incidents.first.step_name
      assert_equal 2, incidents.first.runs.size
      assert_not incidents.first.recovered
    end

    test "marks incident recovered when latest step for same name is success after failure" do
      failure = create_run_with_step!(
        status: "stuck",
        step_name: "business_metrics_import",
        step_status: "failed",
        error_message: "timeout",
        started_at: 3.hours.ago
      )
      success = create_run_with_step!(
        status: "partial_failed",
        step_name: "business_metrics_import",
        step_status: "success",
        started_at: 1.hour.ago
      )

      incident = DailyRunIncidentResolver.call.find { |row| row.latest_run == failure }

      assert incident.recovered
      assert_equal success.id, incident.latest_success_step.aicoo_daily_run_id
      assert_equal "latest_step_success", incident.exclusion_reason
    end

    test "does not mark incident recovered when a newer failure exists after success" do
      create_run_with_step!(
        status: "success",
        step_name: "insight_generation",
        step_status: "success",
        started_at: 3.hours.ago
      )
      failure = create_run_with_step!(
        status: "stuck",
        step_name: "insight_generation",
        step_status: "failed",
        error_message: "OOM",
        started_at: 1.hour.ago
      )

      incident = DailyRunIncidentResolver.call.find { |row| row.latest_run == failure }

      assert_not incident.recovered
      assert_nil incident.exclusion_reason
    end

    private

    def create_run_with_step!(status:, step_name:, step_status:, error_message: nil, started_at:)
      run = AicooDailyRun.create!(
        target_date: started_at.to_date,
        status:,
        source: "cron",
        started_at:,
        finished_at: step_status == "success" ? started_at + 5.minutes : nil,
        error_message:
      )
      run.aicoo_daily_run_steps.create!(
        step_name:,
        status: step_status,
        started_at:,
        finished_at: step_status == "success" ? started_at + 5.minutes : started_at + 3.minutes,
        error_message:
      )
      run
    end
  end
end

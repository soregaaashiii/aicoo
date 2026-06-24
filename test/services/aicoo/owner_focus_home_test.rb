require "test_helper"

module Aicoo
  class OwnerFocusHomeTest < ActiveSupport::TestCase
    setup do
      ActionResult.delete_all
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ActionCandidate.update_all(status: "done")
    end

    test "returns top task and counts" do
      run = AicooDailyRun.create!(
        target_date: Date.current,
        status: "failed",
        source: "manual",
        error_message: "boom",
        finished_at: Time.current
      )

      result = OwnerFocusHome.new.call

      assert result.top_task
      assert_equal "daily_run_failure", result.top_task.task_type
      assert_includes result.top_task.title, run.target_date.to_s
      assert_equal 1, result.total_count
      assert_equal 1, result.critical_count
      assert_match "Daily Run", result.summary_message
    end

    test "critical daily run is prioritized over other critical tasks" do
      AicooDailyRun.create!(target_date: Date.current, status: "failed", source: "manual", finished_at: Time.current)
      create_completed_execution_without_result(completed_at: 80.hours.ago)

      result = OwnerFocusHome.new.call

      assert_equal "daily_run_failure", result.top_task.task_type
    end

    test "critical action result registration is prioritized over execution ready" do
      create_completed_execution_without_result(completed_at: 80.hours.ago)
      create_ready_execution

      result = OwnerFocusHome.new.call

      assert_equal "action_result_registration", result.top_task.task_type
      assert_equal "critical", result.top_task.priority
    end

    test "execution ready is prioritized over high opportunity" do
      execution = create_ready_execution
      OpportunityDiscoveryItem.create!(
        title: "High focus opportunity",
        business: businesses(:suelog),
        opportunity_score: 95
      )

      result = OwnerFocusHome.new.call

      assert_equal "action_execution_ready", result.top_task.task_type
      assert_includes result.top_task.title, execution.action_candidate.title
    end

    private

    def create_ready_execution
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Ready focus candidate #{SecureRandom.hex(4)}",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      candidate.create_action_execution!(status: "ready", execution_type: "manual")
    end

    def create_completed_execution_without_result(completed_at:)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Result focus candidate #{SecureRandom.hex(4)}",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at:,
        result_summary: "done"
      )
    end
  end
end

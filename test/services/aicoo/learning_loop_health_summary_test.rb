require "test_helper"

module Aicoo
  class LearningLoopHealthSummaryTest < ActiveSupport::TestCase
    setup do
      ActionResult.delete_all
      ActionExecution.delete_all
    end

    test "returns nil registration rate when no completed executions exist" do
      health = LearningLoopHealthSummary.new.call

      assert_equal 0, health.completed_execution_count
      assert_nil health.registration_rate
      assert_equal "healthy", health.health_status
    end

    test "registration rate below 70 percent is critical" do
      create_completed_execution(with_result: true)
      2.times { create_completed_execution(with_result: false) }

      health = LearningLoopHealthSummary.new.call

      assert_equal 3, health.completed_execution_count
      assert_equal 1, health.action_result_count
      assert_equal 2, health.missing_count
      assert_equal "critical", health.health_status
    end

    test "registration rate below 90 percent is warning" do
      8.times { create_completed_execution(with_result: true) }
      2.times { create_completed_execution(with_result: false) }

      health = LearningLoopHealthSummary.new.call

      assert_equal "warning", health.health_status
      assert_equal 0.8.to_d, health.registration_rate
    end

    private

    def create_completed_execution(with_result:)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Loop health candidate #{SecureRandom.hex(4)}",
        action_type: "seo_improvement",
        status: "approved",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      execution = candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: Time.current,
        result_summary: "done"
      )
      return execution unless with_result

      ActionResult.create!(
        action_execution: execution,
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current
      )
      execution
    end
  end
end

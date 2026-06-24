require "test_helper"

module Aicoo
  class ActionResultRegistrationHealthTest < ActiveSupport::TestCase
    setup do
      ActionExecution.delete_all
    end

    test "pending under 24 hours is attention" do
      create_completed_execution(completed_at: 2.hours.ago)

      health = ActionResultRegistrationHealth.new.call

      assert_equal 1, health.pending_count
      assert_equal 0, health.warning_count
      assert_equal 0, health.critical_count
      assert_equal "attention", health.health_status
    end

    test "over 24 hours is warning" do
      execution = create_completed_execution(completed_at: 25.hours.ago)

      health = ActionResultRegistrationHealth.new.call

      assert_equal 1, health.pending_count
      assert_equal 1, health.warning_count
      assert_equal [ execution.id ], health.warning_execution_ids
      assert_equal "warning", health.health_status
    end

    test "over 72 hours is critical" do
      execution = create_completed_execution(completed_at: 73.hours.ago)

      health = ActionResultRegistrationHealth.new.call

      assert_equal 0, health.warning_count
      assert_equal 1, health.critical_count
      assert_equal [ execution.id ], health.critical_execution_ids
      assert_equal "critical", health.health_status
      assert health.oldest_pending_hours >= 72
    end

    private

    def create_completed_execution(completed_at:)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Registration health candidate #{completed_at.to_i}",
        action_type: "seo_improvement",
        status: "approved",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
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

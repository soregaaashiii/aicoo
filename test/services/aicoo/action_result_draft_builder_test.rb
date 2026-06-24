require "test_helper"

module Aicoo
  class ActionResultDraftBuilderTest < ActiveSupport::TestCase
    test "builds action result draft from completed action execution" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Draft builder candidate",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.6,
        expected_hours: 2,
        cost_yen: 500
      )
      execution = candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        actual_hours: 1.5,
        actual_cost_yen: 300,
        result_summary: "実行完了",
        completed_at: Time.current
      )

      draft = ActionResultDraftBuilder.new(execution).call

      assert_equal execution, draft.action_execution
      assert_equal candidate, draft.action_candidate
      assert_equal candidate.business, draft.business
      assert_equal execution.predicted_profit_yen_snapshot, draft.predicted_expected_profit_yen
      assert_equal execution.predicted_success_probability_snapshot, draft.predicted_success_probability
      assert_includes draft.note, "ActionExecution ##{execution.id}"
      assert_includes draft.note, "実行完了"
    end
  end
end

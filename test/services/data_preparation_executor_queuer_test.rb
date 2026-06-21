require "test_helper"

class DataPreparationExecutorQueuerTest < ActiveSupport::TestCase
  setup do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: false)
  end

  test "does not queue when auto queue setting is false" do
    candidate = create_data_preparation_candidate

    assert_no_difference("AicooExecutorTask.count") do
      result = DataPreparationExecutorQueuer.new.call

      assert result.disabled
      assert_equal 1, result.candidate_count
      assert_equal 0, result.queued_count
      assert_equal 1, result.skipped_count
      assert_equal 1, result.skipped_reasons.fetch("auto queue disabled")
    end

    assert_nil AicooExecutorTask.unfinished_for_action_candidate(candidate)
  end

  test "queues data preparation candidates as approval pending when enabled" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)
    candidate = create_data_preparation_candidate

    assert_difference("AicooExecutorTask.count", 1) do
      result = DataPreparationExecutorQueuer.new.call

      assert_not result.disabled
      assert_equal 1, result.candidate_count
      assert_equal 1, result.queued_count
      assert_equal 0, result.skipped_count
    end

    task = AicooExecutorTask.last
    assert_equal "approval_pending", task.status
    assert_equal "data_preparation", task.execution_type
    assert_equal "action_candidate", task.source_type
    assert_equal candidate.id, task.source_id
    assert_includes task.execution_prompt, "ActionResultを記録してください"
  end

  test "does not duplicate unfinished executor tasks" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)
    candidate = create_data_preparation_candidate
    AicooExecutor::TaskBuilder.from_action_candidate(candidate)

    assert_no_difference("AicooExecutorTask.count") do
      result = DataPreparationExecutorQueuer.new.call

      assert_equal 1, result.candidate_count
      assert_equal 0, result.queued_count
      assert_equal 1, result.skipped_count
      assert_equal 1, result.skipped_reasons.fetch("already queued")
    end
  end

  private

  def create_data_preparation_candidate
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "ActionResult不足を解消する",
      action_type: "data_preparation",
      status: "idea",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.5,
      expected_hours: 1,
      execution_prompt: "ActionResultを記録してください",
      metadata: {
        "missing_type" => [ "action_results" ],
        "required_count" => { "action_results" => 10 },
        "current_count" => { "action_results" => 0 },
        "business_id" => businesses(:suelog).id
      }
    )
  end
end

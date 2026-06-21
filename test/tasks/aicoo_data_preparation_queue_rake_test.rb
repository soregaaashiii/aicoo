require "test_helper"
require "rake"

class AicooDataPreparationQueueRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:auto_queue_data_preparation")
    Rake::Task["aicoo:auto_queue_data_preparation"].reenable
  end

  test "auto_queue_data_preparation task exists" do
    assert Rake::Task.task_defined?("aicoo:auto_queue_data_preparation")
  end

  test "auto_queue_data_preparation queues candidates with force mode" do
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Rake data preparation task",
      action_type: "data_preparation",
      status: "idea",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.5,
      expected_hours: 1,
      execution_prompt: "実行結果を記録してください"
    )

    assert_difference("AicooExecutorTask.count", 1) do
      output, = capture_io do
        Rake::Task["aicoo:auto_queue_data_preparation"].invoke
      end

      assert_includes output, "AICOO data_preparation auto queue"
      assert_includes output, "data_preparation_candidates_count=1"
      assert_includes output, "data_preparation_auto_queued_count=1"
    end
  end
end

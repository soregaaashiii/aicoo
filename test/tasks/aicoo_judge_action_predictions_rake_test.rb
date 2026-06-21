require "test_helper"
require "rake"

class AicooJudgeActionPredictionsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:judge_action_predictions")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "judge_action_predictions task exists" do
    assert Rake::Task.task_defined?("aicoo:judge_action_predictions")
  end

  test "prints action prediction summaries" do
    output, = capture_io do
      task.invoke
    end

    assert_includes output, "AICOO action prediction judge"
    assert_includes output, "generation_source:"
    assert_includes output, "business:"
    assert_includes output, "action_type:"
    assert_includes output, "metric_rule:"
  end

  private

  def task
    Rake::Task["aicoo:judge_action_predictions"]
  end
end

require "test_helper"
require "rake"

class AicooMetricActionCandidatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:generate_action_candidates_from_metrics")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "generate_action_candidates_from_metrics task exists" do
    assert Rake::Task.task_defined?("aicoo:generate_action_candidates_from_metrics")
  end

  test "runs metric action candidate generation" do
    output, = capture_io do
      task.invoke
    end

    assert_includes output, "AICOO metric action candidate generation started"
    assert_includes output, "created_action_candidate_count="
    assert_includes output, "skipped_count="
  end

  private

  def task
    Rake::Task["aicoo:generate_action_candidates_from_metrics"]
  end
end

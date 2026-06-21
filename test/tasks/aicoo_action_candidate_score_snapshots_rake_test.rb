require "test_helper"
require "rake"

class AicooActionCandidateScoreSnapshotsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:snapshot_action_candidate_scores")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "snapshot task creates score snapshots" do
    output, = capture_io do
      task.invoke("2026-06-21")
    end

    assert_includes output, "AICOO ActionCandidate score snapshot recorded_on=2026-06-21"
    assert_includes output, "snapshots_created_count="
  end

  private

  def task
    Rake::Task["aicoo:snapshot_action_candidate_scores"]
  end
end

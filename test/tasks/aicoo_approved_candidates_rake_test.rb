require "test_helper"
require "rake"

class AicooApprovedCandidatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:queue_approved_candidates")
    Rake::Task["aicoo:queue_approved_candidates"].reenable
  end

  test "queue_approved_candidates task exists" do
    assert Rake::Task.task_defined?("aicoo:queue_approved_candidates")
  end

  test "queue_approved_candidates queues approved candidates" do
    create_approved_candidate

    assert_difference("AicooExecutorTask.count", 1) do
      output, = capture_io do
        Rake::Task["aicoo:queue_approved_candidates"].invoke
      end

      assert_includes output, "AICOO queue approved candidates"
      assert_includes output, "target_count=1"
      assert_includes output, "created_count=1"
    end
  end

  private

  def create_approved_candidate
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Rake approved queue candidate",
      action_type: "other",
      status: "approved",
      approved_at: Time.current,
      approved_by: "owner",
      immediate_value_yen: 5_000,
      success_probability: 1,
      expected_hours: 1,
      confidence_score: 80
    )
  end
end

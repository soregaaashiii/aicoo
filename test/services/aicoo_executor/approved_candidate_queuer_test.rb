require "test_helper"

module AicooExecutor
  class ApprovedCandidateQueuerTest < ActiveSupport::TestCase
    test "creates auto revision tasks for approved candidates" do
      action_candidate = create_approved_action_candidate(action_type: "seo_article")

      assert_difference("AutoRevisionTask.count", 1) do
        result = ApprovedCandidateQueuer.queue_all!

        assert_equal 1, result.target_count
        assert_equal 1, result.created_count
        assert_equal 0, result.skipped_count
      end

      task = AutoRevisionTask.last
      assert_equal "waiting_approval", task.status
      assert_equal action_candidate, task.action_candidate
      assert_equal "approved_candidate_queuer", task.generated_by
      assert_equal "approved", action_candidate.reload.status
      assert_nil action_candidate.executor_queued_at
    end

    test "does not duplicate active auto revision tasks" do
      action_candidate = create_approved_action_candidate
      AutoRevisionTask.from_action_candidate(action_candidate)

      assert_no_difference("AutoRevisionTask.count") do
        result = ApprovedCandidateQueuer.queue_all!

        assert_equal 1, result.target_count
        assert_equal 0, result.created_count
        assert_equal 1, result.skipped_count
        assert_equal 1, result.skipped_reasons.fetch("既にAutoRevisionTaskへ統合済み")
      end

      assert_equal "approved", action_candidate.reload.status
    end

    private

    def create_approved_action_candidate(attributes = {})
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          title: "Approved queue action",
          action_type: "other",
          status: "approved",
          approved_at: Time.current,
          approved_by: "owner",
          immediate_value_yen: 5_000,
          success_probability: 1,
          expected_hours: 1,
          confidence_score: 80
        }.merge(attributes)
      )
    end
  end
end

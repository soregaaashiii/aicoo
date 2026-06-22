require "test_helper"

module AicooExecutor
  class ApprovedCandidateQueuerTest < ActiveSupport::TestCase
    test "queues approved candidates into executor and marks them queued" do
      action_candidate = create_approved_action_candidate(action_type: "seo_article")

      assert_difference("AicooExecutorTask.count", 1) do
        result = ApprovedCandidateQueuer.queue_all!

        assert_equal 1, result.target_count
        assert_equal 1, result.created_count
        assert_equal 0, result.skipped_count
      end

      task = AicooExecutorTask.last
      assert_equal "approval_pending", task.status
      assert_equal "seo_content", task.execution_type
      assert_equal action_candidate.id, task.source_id
      assert_equal "executor_queued", action_candidate.reload.status
      assert action_candidate.executor_queued_at.present?
    end

    test "does not duplicate unfinished executor tasks" do
      action_candidate = create_approved_action_candidate
      AicooExecutor::TaskBuilder.from_action_candidate(action_candidate)

      assert_no_difference("AicooExecutorTask.count") do
        result = ApprovedCandidateQueuer.queue_all!

        assert_equal 1, result.target_count
        assert_equal 0, result.created_count
        assert_equal 1, result.skipped_count
        assert_equal 1, result.skipped_reasons.fetch("既に実行指示へ送信済み")
      end

      assert_equal "executor_queued", action_candidate.reload.status
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

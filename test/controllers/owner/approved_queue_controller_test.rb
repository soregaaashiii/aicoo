require "test_helper"

module Owner
  class ApprovedQueueControllerTest < ActionDispatch::IntegrationTest
    test "shows approved queue candidates" do
      candidate = create_approved_candidate(title: "承認済みSEO改善")

      get owner_approved_queue_url

      assert_response :success
      assert_includes response.body, "承認済みキュー"
      assert_includes response.body, candidate.title
      assert_includes response.body, "Executorへ送る"
    end

    test "queues selected candidates into executor" do
      candidate = create_approved_candidate

      assert_difference("AicooExecutorTask.count", 1) do
        post queue_selected_owner_approved_queue_url, params: {
          action_candidate_ids: [ candidate.id ]
        }
      end

      assert_redirected_to owner_approved_queue_url
      assert_equal "executor_queued", candidate.reload.status
      assert_equal "approval_pending", AicooExecutorTask.last.status
      assert_includes flash[:notice], "送信対象 1件"
      assert_includes flash[:notice], "作成 1件"
    end

    test "bulk queue skips candidates with unfinished executor tasks" do
      candidate = create_approved_candidate
      AicooExecutor::TaskBuilder.from_action_candidate(candidate)

      assert_no_difference("AicooExecutorTask.count") do
        post queue_all_owner_approved_queue_url
      end

      assert_redirected_to owner_approved_queue_url
      assert_equal "executor_queued", candidate.reload.status
      assert_includes flash[:notice], "スキップ 1件"
      assert_includes flash[:notice], "既にExecutor登録済み"
    end

    private

    def create_approved_candidate(attributes = {})
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          title: "Approved queue candidate",
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

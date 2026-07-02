require "test_helper"

module Owner
  class ApprovedQueueControllerTest < ActionDispatch::IntegrationTest
    test "redirects approved queue index to auto revision tasks" do
      create_approved_candidate(title: "承認済みSEO改善")

      get owner_approved_queue_url

      assert_redirected_to auto_revision_tasks_url(status: "waiting_approval")
      assert_includes flash[:notice], "承認済みキューはAutoRevisionTaskへ統合しました"
    end

    test "selected candidates are converted to auto revision tasks" do
      candidate = create_approved_candidate

      assert_difference("AutoRevisionTask.count", 1) do
        post queue_selected_owner_approved_queue_url, params: {
          action_candidate_ids: [ candidate.id ]
        }
      end

      assert_redirected_to auto_revision_tasks_url(status: "waiting_approval")
      assert_equal "approved", candidate.reload.status
      assert_equal "waiting_approval", AutoRevisionTask.last.status
      assert_equal candidate, AutoRevisionTask.last.action_candidate
      assert_includes flash[:notice], "承認済みキューはAutoRevisionTaskへ統合しました"
    end

    test "bulk queue skips candidates with active auto revision tasks" do
      candidate = create_approved_candidate
      AutoRevisionTask.from_action_candidate(candidate)

      assert_no_difference("AutoRevisionTask.count") do
        post queue_all_owner_approved_queue_url
      end

      assert_redirected_to auto_revision_tasks_url(status: "waiting_approval")
      assert_equal "approved", candidate.reload.status
      assert_includes flash[:notice], "承認済みキューはAutoRevisionTaskへ統合しました"
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

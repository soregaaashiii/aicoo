require "test_helper"

module Owner
  class AutoRevisionLoopsControllerTest < ActionDispatch::IntegrationTest
    test "shows auto revision loop page" do
      get owner_auto_revision_loop_url

      assert_response :success
      assert_includes response.body, "自動改修ループ"
      assert_includes response.body, "次に押すボタン"
    end

    test "creates action result from loop page" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.action_result&.destroy!

      assert_difference("ActionResult.count", 1) do
        post owner_auto_revision_loop_action_results_url, params: {
          action_candidate_id: candidate.id,
          action_result: {
            executed_on: Date.current,
            evaluated_on: Date.current,
            actual_revenue_yen: 1000,
            actual_profit_yen: 800,
            actual_proxy_score_delta: 1.2,
            evaluation_status: "pending",
            note: "Owner loop test"
          }
        }
      end

      assert_redirected_to owner_auto_revision_loop_url(selected: "action_candidate:#{candidate.id}", anchor: "selected-task")
      assert_equal candidate, ActionResult.last.action_candidate
    end

    test "creates auto revision task from loop page without leaving owner flow" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.auto_revision_tasks.destroy_all

      assert_difference("AutoRevisionTask.count", 1) do
        post create_task_owner_auto_revision_loop_candidate_url(candidate)
      end

      task = AutoRevisionTask.last
      assert_redirected_to owner_auto_revision_loop_url(selected: "auto_revision_task:#{task.id}", anchor: "selected-task")
      assert_equal candidate, task.action_candidate
    end
  end
end

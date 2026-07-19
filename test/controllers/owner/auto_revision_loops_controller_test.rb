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
            actual_clicks_delta: 7,
            actual_proxy_score_delta: 1.2,
            metadata: {
              manual_actuals: {
                ctr: "0.03",
                average_position: "9.8",
                conversions: "1"
              }
            },
            evaluation_status: "pending",
            note: "Owner loop test"
          }
        }
      end

      assert_redirected_to owner_auto_revision_loop_url(selected: "action_candidate:#{candidate.id}", anchor: "selected-task")
      result = ActionResult.last
      assert_equal candidate, result.action_candidate
      assert_equal "evaluated", result.evaluation_status
      assert_equal true, result.metadata["manual_actuals_recorded"]
      assert_equal 7, result.actual_clicks_delta
      assert_equal "0.03", result.metadata.dig("manual_actuals", "ctr")
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

    test "github issue direct get redirects back instead of 404" do
      candidate = action_candidates(:nagazakicho_article)
      task = AutoRevisionTask.from_action_candidate(candidate)

      get create_github_issue_owner_auto_revision_loop_task_url(task)

      assert_redirected_to owner_auto_revision_loop_url(selected: "auto_revision_task:#{task.id}", anchor: "selected-task")
      assert_match "画面内のボタン", flash[:alert]
    end

    test "missing github issue task redirects to loop instead of 404" do
      post "/owner/auto_revision_loop/auto_revision_tasks/999999/create_github_issue"

      assert_redirected_to owner_auto_revision_loop_url(anchor: "revision-queue")
      assert_match "見つかりません", flash[:alert]
    end
  end
end

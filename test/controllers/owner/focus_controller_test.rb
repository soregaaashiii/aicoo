require "test_helper"

module Owner
  class FocusControllerTest < ActionDispatch::IntegrationTest
    test "shows owner focus home with quick actions" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Focus page execution",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      candidate.create_action_execution!(status: "ready", execution_type: "manual")

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Owner Focus Home"
      assert_includes response.body, "次にやるべき1件"
      assert_includes response.body, "Focus page execution"
      assert_includes response.body, "実行開始"
      assert_includes response.body, "スキップ"
      assert_includes response.body, "すべてのタスクを見る"
    end

    test "shows empty state" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今すぐ処理すべきタスクはありません。"
    end
  end
end

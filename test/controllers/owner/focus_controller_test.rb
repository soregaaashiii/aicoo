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
      assert_includes response.body, "Owner Home"
      assert_includes response.body, "次にやる1件"
      assert_includes response.body, "Focus page execution"
      assert_includes response.body, "実行開始"
      assert_includes response.body, "今日の処理状況"
      assert_includes response.body, "Execution Ready"
      assert_includes response.body, "Result Registration"
      assert_includes response.body, "Calibration Pending"
      assert_includes response.body, "Explore Review"
      assert_includes response.body, "システム状態"
      assert_includes response.body, "Daily Run"
      assert_includes response.body, "Learning"
      assert_includes response.body, "詳細画面"
    end

    test "shows empty state" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今すぐ処理すべきタスクはありません。"
    end
  end
end

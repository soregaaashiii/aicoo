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
      candidate.update_columns(
        metadata: candidate.metadata.merge(
          "action_expansion" => {
            "expanded" => true,
            "recommended_tasks" => [ "SEOタイトル改訂" ],
            "target" => "/focus-page",
            "completion_criteria" => [ "タイトルが改訂されている", "ActionResult登録用メモがある" ],
            "warning" => false
          }
        )
      )
      candidate.create_action_execution!(status: "ready", execution_type: "manual")

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今日やること"
      assert_includes response.body, "次にやる1件"
      assert_includes response.body, "/focus-pageでSEOタイトル改訂を行う"
      assert_includes response.body, "実行する"
      assert_includes response.body, "なぜやるか"
      assert_includes response.body, "何をするか"
      assert_includes response.body, "SEOタイトル改訂"
      assert_includes response.body, "/focus-page"
      assert_includes response.body, "完了条件"
      assert_includes response.body, "詳細を見る"
      assert_includes response.body, "後でやる"
      assert_includes response.body, "今日の処理状況"
      assert_includes response.body, "実行待ち"
      assert_includes response.body, "結果登録待ち"
      assert_includes response.body, "評価式承認待ち"
      assert_includes response.body, "探索確認待ち"
      assert_includes response.body, "今日の判断記録"
      assert_includes response.body, "重大な連携注意"
      assert_includes response.body, "システム状態"
      assert_includes response.body, "自動巡回"
      assert_includes response.body, "学習状態"
      assert_includes response.body, "詳細画面"
      assert_not_includes response.body, "ActionCandidate"
      assert_not_includes response.body, "metadata"
      assert_not_includes response.body, "Analytics Import"
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

    test "shows pending opportunity as next action with opportunity quick actions" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "Focus pending opportunity",
        summary: "低コストLPで検証できる",
        source_type: "google_trends",
        opportunity_type: "lp_test",
        status: "pending",
        opportunity_score: 95,
        expected_value_yen: 120_000,
        confidence: 88
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Focus opportunity"
      assert_includes response.body, "¥120,000"
      assert_includes response.body, "成功率"
      assert_includes response.body, "低コストLPで検証できる"
      assert_includes response.body, "実行する"
      assert_includes response.body, "詳細を見る"
      assert_includes response.body, "後でやる"
      assert_not_includes response.body, "却下"
      assert_includes response.body, focus_convert_to_candidate_owner_opportunity_path(opportunity)
      assert_includes response.body, "機会確認待ち"
    end

    test "shows codex prompt draft task when approved candidate has no draft" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Codex prompt focus candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Codex prompt focus candidate"
      assert_includes response.body, "実行する"
      assert_includes response.body, generate_codex_prompt_draft_action_candidate_path(candidate)
    end

    test "shows owner execution queue when no focus task exists" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      item = OwnerExecutionQueueItem.create!(
        item_type: "opportunity",
        item_id: 1,
        title: "Focus queue item",
        risk_level: "low",
        status: "pending",
        due_on: Date.current,
        priority_score: 99,
        reason: "今日処理する"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "あとで処理する候補"
      assert_includes response.body, "Focus queue item"
      assert_includes response.body, skip_owner_execution_queue_item_path(item)
      assert_not_includes response.body, complete_owner_execution_queue_item_path(item)
    end
  end
end

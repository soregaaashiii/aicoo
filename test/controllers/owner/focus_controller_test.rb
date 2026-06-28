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
      assert_includes response.body, "今日やることランキング"
      assert_includes response.body, "おすすめ"
      assert_includes response.body, "収益順"
      assert_includes response.body, "時給順"
      assert_includes response.body, "学習価値順"
      assert_includes response.body, "/focus-pageでSEOタイトル改訂を行う"
      assert_includes response.body, "作業開始"
      assert_includes response.body, "おすすめ理由"
      assert_includes response.body, "期待利益"
      assert_includes response.body, "期待時給"
      assert_includes response.body, "学習価値"
      assert_includes response.body, "成功率"
      assert_includes response.body, "SEOタイトル改訂"
      assert_includes response.body, "完了条件"
      assert_includes response.body, "未処理"
      assert_includes response.body, "作業開始"
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
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今日やることランキング"
      assert_includes response.body, "今すぐ処理すべき作業はありません。"
    end

    test "does not show system business in critical integration warnings" do
      Business.create!(
        name: "AICOO Analytics Import",
        description: "system import holder",
        status: "launched"
      )

      get owner_focus_url

      assert_response :success
      assert_not_includes response.body, "AICOO Analytics Import"
    end

    test "does not show recent execution result cards or full errors at top" do
      GoogleApiImportRun.create!(
        business: businesses(:suelog),
        status: "failed",
        source_types: %w[ga4],
        fetched_days: 1,
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        error_message: "GA4 metric名が無効です\nraw error full payload should stay out of focus"
      )

      get owner_focus_url

      assert_response :success
      assert_not_includes response.body, "直近の実行結果"
      assert_not_includes response.body, "raw error full payload should stay out of focus"
      assert_includes response.body, "実行履歴"
      assert_includes response.body, admin_execution_runs_path
      assert_includes response.body, "SERP走査"
    end

    test "shows serp scan card and settings link" do
      DataSourceCostProfile.ensure_defaults!
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "serper-key")

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "SERP走査"
      assert_includes response.body, "SERP走査を開始"
      assert_includes response.body, admin_serp_settings_path
      assert_includes response.body, owner_serp_scan_path
      assert_includes response.body, "設定済み"
    end

    test "serp scan start posts through owner focus route" do
      result = Aicoo::Serp::ScanRunner::Result.new(
        started_at: Time.current,
        finished_at: Time.current,
        provider: "serper",
        target_business_count: 1,
        query_count: 1,
        success_count: 1,
        failed_count: 0,
        analyses: []
      )

      with_serp_scan_runner(result) do
        post owner_serp_scan_path
      end

      assert_redirected_to owner_focus_path
      assert_equal "SERP走査が完了しました。1 Business / 1クエリを確認しました。", flash[:notice]
    end

    test "shows pending opportunity as next action with opportunity quick actions" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "外部シグナル検証",
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
      assert_includes response.body, "今日やることランキング"
      assert_includes response.body, "外部シグナル検証を小さく検証する"
      assert_includes response.body, "¥120,000"
      assert_includes response.body, "成功率"
      assert_includes response.body, "低コストLPで検証できる"
      assert_includes response.body, "サービス下書きを作成"
      assert_includes response.body, "詳細を見る"
      assert_includes response.body, "後でやる"
      assert_not_includes response.body, "却下"
      assert_includes response.body, focus_create_business_owner_opportunity_path(opportunity)
      assert_includes response.body, "機会確認待ち"
    end

    test "shows codex prompt draft task when approved candidate has no draft" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      CodexPromptDraft.delete_all
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
      assert_includes response.body, "今日やることランキング"
      assert_includes response.body, "作業開始"
      assert_includes response.body, "詳細を見る"
      assert_includes response.body, generate_codex_prompt_draft_action_candidate_path(candidate)
    end

    test "shows running completed and later action states" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)

      running_candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Running focus candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      running_execution = running_candidate.create_action_execution!(status: "running", execution_type: "manual", started_at: Time.current)
      completed_candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Completed focus candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.7,
        expected_hours: 1
      )
      completed_execution = completed_candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
      later_item = OwnerExecutionQueueItem.create!(
        item_type: "opportunity",
        item_id: 1,
        title: "Later focus item",
        risk_level: "low",
        status: "skipped",
        due_on: Date.current,
        priority_score: 99,
        reason: "あとで確認する"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "作業中"
      assert_includes response.body, "完了する"
      assert_includes response.body, "中断する"
      assert_includes response.body, action_execution_path(running_execution, anchor: "execution-result-form")
      assert_includes response.body, action_execution_path(running_execution, outcome: "blocked", anchor: "execution-result-form")
      assert_includes response.body, "完了済み"
      assert_includes response.body, "結果登録へ"
      assert_includes response.body, new_action_result_path(action_execution_id: completed_execution.id)
      assert_includes response.body, "後でやる"
      assert_includes response.body, "今日に戻す"
      assert_includes response.body, restore_owner_execution_queue_item_path(later_item)
    end

    test "uses recovery labels for daily run system tasks" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      run = AicooDailyRun.create!(
        target_date: Date.current,
        status: "failed",
        started_at: 10.minutes.ago,
        finished_at: 5.minutes.ago,
        error_message: "analytics failed"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "自動巡回を再開する"
      assert_includes response.body, "再実行する"
      assert_includes response.body, aicoo_daily_runs_path
      assert_includes response.body, aicoo_daily_run_path(run)
    end

    test "defer keeps item on focus screen as later state" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Defer focus candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      execution = candidate.create_action_execution!(status: "ready", execution_type: "manual")
      task_key = [ "action_execution_ready", action_execution_path(execution), "#{candidate.title} を実行開始" ].join(":")

      get owner_focus_url
      assert_includes response.body, defer_owner_focus_path
      assert_no_match %r{href="/owner/tasks">後でやる}, response.body

      patch defer_owner_focus_path(task_key:)
      assert_redirected_to owner_focus_path(sort: "recommended")
      follow_redirect!

      assert_response :success
      assert_includes response.body, "後でやる"
      assert_includes response.body, "今日に戻す"
      assert_includes response.body, restore_owner_focus_path
      assert_includes response.body, action_execution_path(execution)
    end

    test "shows owner execution queue when no focus task exists" do
      ActionCandidate.update_all(status: "done")
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
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

    private

    def with_serp_scan_runner(result)
      original_call = Aicoo::Serp::ScanRunner.instance_method(:call)
      Aicoo::Serp::ScanRunner.define_method(:call) { result }
      yield
    ensure
      Aicoo::Serp::ScanRunner.define_method(:call, original_call)
    end
  end
end

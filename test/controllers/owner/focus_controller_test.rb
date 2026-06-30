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
      BusinessActivityLog.create!(
        business: businesses(:suelog),
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "focus-activity",
        title: "記事更新Activity",
        occurred_at: Time.current,
        detected_at: Time.current,
        source_method: "logger",
        idempotency_key: "focus-activity"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今日やること"
      assert_includes response.body, "今日見るBusiness"
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
      assert_includes response.body, "Activity Learning"
      assert_includes response.body, "今日検知したActivity"
      assert_includes response.body, "評価待ちActivity"
      assert_includes response.body, "記事更新Activity"
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

    test "shows serp missing key as optional warning instead of stuck pipeline" do
      DataSourceCostProfile.find_or_create_by!(source_key: "serp") do |profile|
        profile.name = "SERP"
        profile.execution_mode = "manual"
      end.update!(api_key: nil)
      item = IdeaPipelineItem.create!(
        title: "Stuck SERP Idea",
        short_description: "SERPで止まる",
        problem: "検索検証が進まない",
        target_user: "Owner",
        revenue_model: "月額",
        mvp_concept: "LP",
        lp_concept: "LP",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80,
        status: "owner_approved",
        final_score: 80,
        evaluated_at: 2.hours.ago
      )
      Aicoo::IdeaPipeline::LandingPageBuilder.new(item).call
      Aicoo::IdeaPipeline::Publisher.new(item).call
      run = Aicoo::PipelineEngine.new(item).call
      old_time = 2.hours.ago.iso8601
      states = run.stage_states
      states[run.current_stage]["started_at"] = old_time
      run.update!(stage_states: states, metadata: run.metadata.merge("stage_entered_at" => old_time))

      get owner_focus_url

      assert_response :success
      assert_not_includes response.body, "missing_serp_key"
      assert_includes response.body, "任意設定の警告"
      assert_includes response.body, "SERP未設定"
      assert_includes response.body, "既存データによる改善ループは継続します"
    end

    test "shows serp scan card and settings link" do
      DataSourceCostProfile.ensure_defaults!
      DataSourceCostProfile.find_by!(source_key: "serp").update!(
        api_key: "serper-key",
        monthly_budget_yen: 10,
        monthly_spend_yen: 9,
        metadata: {
          Aicoo::Serp::ScanPlan::METADATA_LIMIT_KEY => 60,
          Aicoo::Serp::ScanPlan::METADATA_UNIT_COST_KEY => 1
        }
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "SERP走査"
      assert_includes response.body, "SERP走査を開始"
      assert_includes response.body, admin_serp_settings_path
      assert_includes response.body, owner_serp_scan_path
      assert_includes response.body, owner_serp_scan_settings_path
      assert_includes response.body, "設定済み"
      assert_includes response.body, "Limit"
      assert_includes response.body, "高コストです"
      assert_includes response.body, "今回の実行で月予算を超えます"
      assert_includes response.body, "実行前コスト"
    end

    test "shows business auto revision summary" do
      businesses(:suelog).update!(auto_revision_mode: "automatic", auto_deploy_mode: "automatic")
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "承認待ち改訂候補",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      AutoRevisionTask.create!(
        business: businesses(:suelog),
        action_candidate: candidate,
        title: "承認待ち改訂",
        execution_prompt: "SEOタイトルを改善してください。",
        status: "waiting_approval",
        risk_level: "medium",
        priority_score: 100
      )
      AutoRevisionRunLog.create!(
        business: businesses(:suelog),
        status: "precheck_failed",
        auto_revision_mode: "automatic",
        risk_level: "low",
        message: "Google接続が未設定です"
      )
      AutoRevisionRunLog.create!(
        business: businesses(:suelog),
        status: "deploy_pending",
        auto_revision_mode: "automatic",
        risk_level: "low",
        base_commit_sha: "rollback-sha",
        message: "Deploy承認待ち"
      )
      AutoRevisionRunLog.create!(
        business: businesses(:suelog),
        status: "failed",
        auto_revision_mode: "automatic",
        risk_level: "low",
        deploy_result: "failed",
        message: "Deploy失敗"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "自動改訂ON"
      assert_includes response.body, "自動デプロイON"
      assert_includes response.body, "改訂承認待ち"
      assert_includes response.body, "Deploy承認待ち"
      assert_includes response.body, "Deploy失敗"
      assert_includes response.body, "Rollback可能"
      assert_includes response.body, "改訂停止"
      assert_includes response.body, "自動改訂対象のBusinessがあります"
    end

    test "updates serp scan limit from owner focus" do
      DataSourceCostProfile.ensure_defaults!

      patch owner_serp_scan_settings_path, params: { serp_scan: { limit: "25" } }

      assert_redirected_to owner_focus_path
      assert_equal "SERP走査Limitを25に保存しました。", flash[:notice]
      assert_equal 25, Aicoo::Serp::ScanPlan.configured_limit(DataSourceCostProfile.find_by!(source_key: "serp"))
    end

    test "shows serp running status on owner focus" do
      businesses(:suelog).serp_analyses.create!(
        keyword: "大阪 喫煙 カフェ",
        search_engine: "google",
        location: "Japan",
        device: "desktop",
        provider: "serper",
        status: "running",
        analyzed_at: 1.minute.ago,
        result_count: 0,
        raw_summary: {
          "scan_batch_id" => "running-batch",
          "scan_started_at" => 1.minute.ago.iso8601,
          "limit" => 10
        }
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "SERP走査中..."
      assert_includes response.body, "現在 吸えログ"
      assert_includes response.body, "対象 1事業"
    end

    test "shows latest serp completion summary on owner focus" do
      businesses(:suelog).serp_analyses.create!(
        keyword: "大阪 喫煙 カフェ",
        search_engine: "google",
        location: "Japan",
        device: "desktop",
        provider: "serper",
        status: "success",
        analyzed_at: 2.minutes.ago,
        result_count: 8,
        raw_summary: {
          "scan_batch_id" => "success-batch",
          "scan_started_at" => 3.minutes.ago.iso8601,
          "scan_finished_at" => 2.minutes.ago.iso8601,
          "limit" => 10
        }
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "最新のSERP走査"
      assert_includes response.body, "SERP走査が完了しました"
      assert_includes response.body, "取得 8件"
      assert_includes response.body, "実行時間"
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
        result_count: 10,
        duration_seconds: 1.2,
        estimated_cost_yen: 3,
        limit: 10,
        scan_batch_id: "test-batch",
        analyses: []
      )

      with_serp_scan_runner(result) do
        post owner_serp_scan_path
      end

      assert_redirected_to owner_focus_path
      assert_equal "SERP走査が完了しました。1 Business / 1クエリ / 10件取得 / 約3円 / 1.2秒", flash[:notice]
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

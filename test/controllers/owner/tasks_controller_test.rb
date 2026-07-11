require "test_helper"

module Owner
  class TasksControllerTest < ActionDispatch::IntegrationTest
    test "shows owner task inbox" do
      create_healthy_daily_run
      create_done_today_candidate
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Owner tasks page candidate",
        status: "idea",
        action_type: "other",
        immediate_value_yen: 5_000,
        success_probability: 1,
        expected_hours: 1
      )

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "システム障害・確認タスク"
      assert_includes response.body, "Todayと同じ優先順位"
      assert_includes response.body, "確認ダイジェスト"
      assert_includes response.body, "Daily Run Health"
      assert_includes response.body, "本日生成提案"
      assert_includes response.body, "pending補正"
      assert_includes response.body, "結果登録待ち"
      assert_includes response.body, "最古登録待ち"
      assert_includes response.body, "Owner tasks page candidate"
      assert_includes response.body, "優先度"
      assert_includes response.body, "種別"
      assert_includes response.body, "重要タスクがあります。今日中に確認してください。"
      assert_includes response.body, "改修開始"
      assert_includes response.body, "却下"
      assert_includes response.body, "詳細を見る"
    end

    test "filters owner task inbox" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        approval_requested_at: Time.current
      )

      get owner_tasks_url(priority: "critical", task_type: "calibration_approval")

      assert_response :success
      assert_includes response.body, "seo_article"
      assert_includes response.body, "評価式反映"
    end

    test "shows daily run quick actions" do
      AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "failed",
        source: "manual",
        error_message: "boom",
        finished_at: Time.current
      )

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "再実行"
      assert_includes response.body, "詳細を見る"
    end

    test "shows digest warning for critical tasks" do
      create_healthy_daily_run
      create_done_today_candidate
      ActionPredictionCalibration.create!(
        action_type: "danger_digest",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        approval_requested_at: Time.current
      )

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "Criticalタスクがあります。最優先で確認してください。"
      assert_includes response.body, "危険度の高い評価式補正が承認待ちです。"
      assert_includes response.body, "最優先タスク"
      assert_includes response.body, "推奨アクション"
    end

    test "shows owner execution queue" do
      item = OwnerExecutionQueueItem.create!(
        item_type: "opportunity",
        item_id: 1,
        business: businesses(:suelog),
        title: "Owner queue opportunity",
        risk_level: "low",
        status: "pending",
        expected_value_yen: 50_000,
        priority_score: 42_000,
        due_on: Date.current,
        reason: "今日処理する"
      )

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "今日の実行キュー"
      assert_includes response.body, "Owner queue opportunity"
      assert_includes response.body, "Pending"
      assert_includes response.body, "今日のDecision Log"
      assert_includes response.body, complete_owner_execution_queue_item_path(item)
      assert_includes response.body, skip_owner_execution_queue_item_path(item)
    end

    test "shows recent completion logs" do
      candidate = action_candidates(:nagazakicho_article)
      OwnerTaskCompletionLog.record_success!(
        task_type: "action_candidate_approval",
        target: candidate,
        action_label: "承認",
        message: "ActionCandidate『#{candidate.title}』を承認しました。承認待ちタスクから削除されました。"
      )

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "直近処理済み"
      assert_includes response.body, "承認待ちタスクから削除されました"
      assert_includes response.body, "ActionCandidate"
    end

    test "explains empty task inbox completion history" do
      ActionCandidate.update_all(status: "done")
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)

      get owner_tasks_url

      assert_response :success
      assert_includes response.body, "今すぐ確認が必要なタスクはありません。開始・却下・再実行済みの内容は下の「直近処理済み」で確認できます。"
    end

    private

    def create_healthy_daily_run
      AicooDailyRun.create!(
        target_date: Date.current,
        status: "success",
        source: "manual",
        started_at: 10.minutes.ago,
        finished_at: 5.minutes.ago
      )
    end

    def create_done_today_candidate
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Today completed health baseline",
        status: "done",
        action_type: "other",
        immediate_value_yen: 1_000,
        success_probability: 1,
        expected_hours: 1
      )
    end
  end
end

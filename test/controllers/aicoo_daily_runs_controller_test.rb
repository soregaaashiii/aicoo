require "test_helper"

class AicooDailyRunsControllerTest < ActionDispatch::IntegrationTest
  test "shows daily run index" do
    started_at = Time.current.change(sec: 0)
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", started_at:, finished_at: started_at + 5.minutes, source: "cron")
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "skipped",
      metadata: { warning: true, reason: "analytics_optional_unavailable" }
    )
    serp_run = SerpRun.create!(
      status: "success",
      started_at: started_at + 2.minutes,
      finished_at: started_at + 3.minutes,
      executed_by: "scheduler",
      query_count: 4,
      success_count: 3,
      failure_count: 1,
      candidate_count: 2,
      credit_estimate: 4,
      metadata: {
        plan: {
          rows: [
            { status: "run", query: "梅田 喫煙" },
            { status: "skipped", query: "難波 喫煙", reason: "recently_fetched_24h" }
          ]
        }
      }
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "AICOO Daily Run"
    assert_includes response.body, "SERP Run"
    assert_includes response.body, "最新SERP Run"
    assert_includes response.body, "関連SERP Run"
    assert_includes response.body, admin_serp_settings_path(serp_run_id: serp_run.id)
    assert_includes response.body, "Daily Run調査履歴"
    assert_includes response.body, "検索・絞り込み"
    assert_not_includes response.body, "直近10Run比較"
    assert_includes response.body, "source"
    assert_includes response.body, "Analytics"
    assert_includes response.body, "Insight"
    assert_includes response.body, "100%"
  end

  test "filters daily runs by warning" do
    warning_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "cron")
    warning_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "skipped",
      metadata: { warning: true, reason: "analytics_optional_unavailable" }
    )
    normal_run = AicooDailyRun.create!(target_date: 2.days.ago.to_date, status: "success", source: "manual")

    get aicoo_daily_runs_url, params: { warning: "1" }

    assert_response :success
    assert_includes response.body, aicoo_daily_run_path(warning_run)
    history_section = response.body.split("Daily Run調査履歴").last
    assert_not_includes history_section, aicoo_daily_run_path(normal_run)
  end

  test "shows running daily run status on index" do
    daily_run = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "running",
      source: "manual",
      started_at: 10.minutes.ago
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "action_generation",
      status: "running",
      started_at: 2.minutes.ago,
      metadata: {
        current_business_name: "吸えログ",
        current_business_index: 42,
        total_business_count: 183,
        current_candidate_count: 412,
        total_candidate_count: 801
      }
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "現在の実行状態"
    assert_includes response.body, "実行中"
    assert_includes response.body, "Run ID"
    assert_includes response.body, "stuck判定"
    assert_includes response.body, "通常実行中"
    assert_includes response.body, "最終ログ"
    assert_includes response.body, "Action Generation"
    assert_includes response.body, "吸えログ 42 / 183"
    assert_includes response.body, "残り時間"
    assert_includes response.body, "data-aicoo-auto-refresh=\"5000\""
    assert_includes response.body, "data-daily-run-progress-key=\"list-#{daily_run.id}\""
    assert_includes response.body, "\"Accept\": \"text/html\""
    assert_includes response.body, aicoo_daily_run_path(daily_run)
  end

  test "shows not running message when no daily run is running" do
    AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "success",
      source: "cron",
      started_at: 1.hour.ago,
      finished_at: 50.minutes.ago
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "Daily Runは現在実行されていません。"
    assert_includes response.body, "最終実行"
    assert_not_includes response.body, "通常実行中"
  end

  test "compact operation status shows only the latest running daily run" do
    older_run = AicooDailyRun.create!(
      target_date: 2.days.ago.to_date,
      status: "running",
      source: "cron",
      started_at: 20.minutes.ago
    )
    newer_run = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "running",
      source: "manual",
      started_at: 10.minutes.ago
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "data-daily-run-progress-key=\"operation-#{newer_run.id}\""
    assert_not_includes response.body, "data-daily-run-progress-key=\"operation-#{older_run.id}\""
  end

  test "shows stale running daily run as stuck possibility consistently" do
    daily_run = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "running",
      source: "cron",
      started_at: 45.minutes.ago,
      run_log: "still running"
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "running",
      started_at: 44.minutes.ago,
      metadata: { message: "fetching analytics" }
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "stuckの可能性あり"
    assert_includes response.body, "analytics_fetch"
    assert_includes response.body, "fetching analytics"
  end

  test "shows daily run detail" do
    started_at = Time.current.change(sec: 0)
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "manual", run_log: "done", started_at:, finished_at: started_at + 6.minutes)
    serp_run = SerpRun.create!(
      status: "success",
      started_at: started_at + 2.minutes,
      finished_at: started_at + 4.minutes,
      executed_by: "manual",
      query_count: 5,
      success_count: 4,
      failure_count: 1,
      candidate_count: 3,
      credit_estimate: 5,
      metadata: {
        plan: {
          rows: [
            { status: "run", query: "梅田 喫煙" },
            { status: "skipped", query: "難波 喫煙", reason: "daily_limit_reached" }
          ]
        }
      }
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "action_generation",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      duration_seconds: 60,
      error_message: "generation boom",
      metadata: {
        generated_count: 0,
        memory_start: { rss_mb: "128.0" },
        memory_finish: { rss_mb: "141.5" },
        memory_delta_mb: "13.5"
      }
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "calibration",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      duration_seconds: 60,
      error_message: "calibration boom"
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      duration_seconds: 60,
      error_message: "analytics boom"
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "owner_task_digest",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      duration_seconds: 60,
      error_message: "digest boom",
      recovery_attempt_count: 1,
      last_recovery_at: 1.minute.ago,
      last_recovery_status: "failed"
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "serp_fetch",
      status: "skipped",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      metadata: {
        warning: true,
        reason: "serp_optional_missing",
        message: "SERP API Key未設定のためスキップしました。"
      }
    )
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Daily Run auto revision candidate",
      action_type: "seo_improvement",
      immediate_value_yen: 1_000,
      success_probability: 0.5,
      expected_hours: 1,
      execution_prompt: "SEOタイトルを改善してください。",
      created_at: Date.yesterday.noon
    )
    AutoRevisionTask.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      title: "Recent auto revision task",
      execution_prompt: "文言を改善する",
      status: "waiting_approval",
      risk_level: "low"
    )

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "AICOO Daily Run詳細"
    assert_includes response.body, "補正できない理由"
    assert_includes response.body, "BusinessMetricDaily不足"
    assert_includes response.body, "Analytics取得"
    assert_includes response.body, "Insight生成"
    assert_includes response.body, "評価関数補正"
    assert_includes response.body, "反映待ち補正"
    assert_includes response.body, "Auto Revision Queue"
    assert_includes response.body, "Auto Revision生成"
    assert_includes response.body, "SERP Run"
    assert_includes response.body, "同時間帯のSERP Run"
    assert_includes response.body, admin_serp_settings_path(serp_run_id: serp_run.id)
    assert_includes response.body, "使用クレジット"
    assert_includes response.body, "基本情報"
    assert_includes response.body, "Run ID"
    assert_includes response.body, "実行サマリー"
    assert_includes response.body, "skipped / warning理由"
    assert_includes response.body, "SERP Optional"
    assert_includes response.body, "Error Log"
    assert_includes response.body, "calibration_ran"
    assert_includes response.body, "calibration_error"
    assert_includes response.body, "AICOO Learning Loop"
    assert_includes response.body, "学習状態"
    assert_includes response.body, "Learning Loop Action Center"
    assert_includes response.body, "実行ログ待ち"
    assert_includes response.body, "結果登録待ち"
    assert_includes response.body, "売上登録待ち"
    assert_includes response.body, "Step Timeline"
    assert_includes response.body, "メモリ"
    assert_includes response.body, "128.0MB"
    assert_includes response.body, "+13.5MB"
    assert_includes response.body, "action_generation"
    assert_includes response.body, "JSON"
    assert_includes response.body, "generation boom"
    assert_includes response.body, "calibration boom"
    assert_includes response.body, "Recovery"
    assert_includes response.body, "再実行不可"
    assert_includes response.body, "Cooldown"
    assert_includes response.body, "Recovery cooldown active"
    assert_not_includes response.body, "直近10Run比較"
    assert_includes response.body, "自動改修タスク候補"
    assert_includes response.body, "Daily Run auto revision candidate"
    assert_includes response.body, "最近作成されたAuto Revision Task"
    assert_includes response.body, "Recent auto revision task"
    assert_includes response.body, "Execution Feasibility Insight"
    assert_includes response.body, "補正提案"
    assert_includes response.body, "Execution Correction Overview"
    assert_includes response.body, "done"
    assert_includes response.body, "Completed"
    assert_includes response.body, "100%"
  end

  test "shows running banner on daily run detail" do
    daily_run = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "running",
      source: "manual",
      started_at: 10.minutes.ago
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "business_playbook_update",
      status: "running",
      started_at: 1.minute.ago,
      metadata: {
        current_business_name: "吸えログ",
        current_business_index: 12,
        total_business_count: 20
      }
    )

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "現在実行中"
    assert_includes response.body, "Daily Runはまだ完了していません"
    assert_includes response.body, "Business Playbook"
    assert_includes response.body, "吸えログ 12 / 20"
    assert_includes response.body, "ETA"
    assert_includes response.body, "Daily Run Step一覧"
    assert_includes response.body, "data-daily-run-progress-key=\"detail-#{daily_run.id}\""
    assert_includes response.body, "同じ対象日の再実行はスキップされます"
  end

  test "shows retained progress and failure details on failed daily run" do
    daily_run = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "failed",
      source: "cron",
      started_at: 20.minutes.ago,
      finished_at: 5.minutes.ago,
      retry_count: 2,
      error_message: "Timeout"
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "success",
      started_at: 20.minutes.ago,
      finished_at: 19.minutes.ago,
      duration_seconds: 60
    )
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "business_metrics_import",
      status: "failed",
      started_at: 19.minutes.ago,
      finished_at: 5.minutes.ago,
      duration_seconds: 14.minutes,
      error_message: "Timeout",
      metadata: { current_business_index: 122, total_business_count: 183 }
    )

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "Failed"
    assert_includes response.body, "Step: business_metrics_import"
    assert_includes response.body, "原因: Timeout"
    assert_includes response.body, "Retry: 2"
    assert_match(/data-progress-percent="[1-9]\d*"/, response.body)
  end

  test "creates daily run from form" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success")

    with_daily_runner_stub(->(target_date:, source:) {
      assert_equal "manual", source
      daily_run
    }) do
      assert_difference("OwnerTaskCompletionLog.count", 1) do
        post aicoo_daily_runs_url, params: { aicoo_daily_run: { target_date: Date.yesterday.to_s } }
      end
    end

    assert_redirected_to aicoo_daily_run_url(daily_run)
    assert_equal "Daily Runを再実行しました。結果はDaily Run詳細で確認してください。", flash[:notice]
    assert_equal "再実行", OwnerTaskCompletionLog.last.action_label
  end

  test "recovers daily run step and records completion log" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "partial_failed", source: "manual")
    step = daily_run.aicoo_daily_run_steps.create!(
      step_name: "owner_task_digest",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      error_message: "digest boom"
    )

    assert_difference("OwnerTaskCompletionLog.count", 1) do
      post recover_aicoo_daily_run_step_url(daily_run, step)
    end

    assert_redirected_to aicoo_daily_run_url(daily_run, anchor: "step-breakdown")
    assert_equal "owner_task_digest step を再実行しました。", flash[:notice]
    assert_equal "success", step.reload.last_recovery_status
    assert_equal "daily_run_step_recovery", OwnerTaskCompletionLog.last.task_type
  end

  private

  def with_daily_runner_stub(replacement)
    original = AicooDailyRunner.method(:run!)
    AicooDailyRunner.define_singleton_method(:run!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    AicooDailyRunner.define_singleton_method(:run!) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end

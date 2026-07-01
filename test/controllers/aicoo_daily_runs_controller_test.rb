require "test_helper"

class AicooDailyRunsControllerTest < ActionDispatch::IntegrationTest
  test "shows daily run index" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", started_at: Time.current, source: "cron")
    daily_run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "skipped",
      metadata: { warning: true, reason: "analytics_optional_unavailable" }
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "AICOO Daily Run"
    assert_includes response.body, "Daily Run調査履歴"
    assert_includes response.body, "検索・絞り込み"
    assert_includes response.body, "直近10Run比較"
    assert_includes response.body, "source"
    assert_includes response.body, "Analytics"
    assert_includes response.body, "Insight"
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
      started_at: 2.minutes.ago
    )

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "現在の実行状態"
    assert_includes response.body, "実行中"
    assert_includes response.body, "action_generation"
    assert_includes response.body, aicoo_daily_run_path(daily_run)
  end

  test "shows daily run detail" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "manual", run_log: "done")
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
    assert_includes response.body, "承認待ち補正"
    assert_includes response.body, "Auto Revision Queue"
    assert_includes response.body, "Auto Revision生成"
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
    assert_includes response.body, "直近10Run比較"
    assert_includes response.body, "自動改修タスク候補"
    assert_includes response.body, "Daily Run auto revision candidate"
    assert_includes response.body, "最近作成されたAuto Revision Task"
    assert_includes response.body, "Recent auto revision task"
    assert_includes response.body, "Execution Feasibility Insight"
    assert_includes response.body, "補正提案"
    assert_includes response.body, "Execution Correction Overview"
    assert_includes response.body, "done"
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
      started_at: 1.minute.ago
    )

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "現在実行中"
    assert_includes response.body, "Daily Runはまだ完了していません"
    assert_includes response.body, "business_playbook_update"
    assert_includes response.body, "同じ対象日の再実行はスキップされます"
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

require "test_helper"

class AicooDailyRunsControllerTest < ActionDispatch::IntegrationTest
  test "shows daily run index" do
    AicooDailyRun.create!(target_date: Date.yesterday, status: "success", started_at: Time.current, source: "cron")

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "AICOO Daily Run"
    assert_includes response.body, "実行履歴"
    assert_includes response.body, "source"
    assert_includes response.body, "Analytics"
    assert_includes response.body, "Insight"
  end

  test "shows daily run detail" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "manual", run_log: "done")
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

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "AICOO Daily Run詳細"
    assert_includes response.body, "補正できない理由"
    assert_includes response.body, "BusinessMetricDaily不足"
    assert_includes response.body, "Analytics取得"
    assert_includes response.body, "Insight生成"
    assert_includes response.body, "評価関数補正"
    assert_includes response.body, "承認待ち補正"
    assert_includes response.body, "calibration_ran"
    assert_includes response.body, "calibration_error"
    assert_includes response.body, "AICOO Learning Loop"
    assert_includes response.body, "学習状態"
    assert_includes response.body, "Learning Loop Action Center"
    assert_includes response.body, "実行ログ待ち"
    assert_includes response.body, "結果登録待ち"
    assert_includes response.body, "売上登録待ち"
    assert_includes response.body, "自動改修タスク候補"
    assert_includes response.body, "Daily Run auto revision candidate"
    assert_includes response.body, "Execution Feasibility Insight"
    assert_includes response.body, "補正提案"
    assert_includes response.body, "Execution Correction Overview"
    assert_includes response.body, "done"
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

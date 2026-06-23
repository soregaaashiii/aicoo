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

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "AICOO Daily Run詳細"
    assert_includes response.body, "補正できない理由"
    assert_includes response.body, "BusinessMetricDaily不足"
    assert_includes response.body, "Analytics取得"
    assert_includes response.body, "Insight生成"
    assert_includes response.body, "AICOO Learning Loop"
    assert_includes response.body, "学習状態"
    assert_includes response.body, "Learning Loop Action Center"
    assert_includes response.body, "実行ログ待ち"
    assert_includes response.body, "結果登録待ち"
    assert_includes response.body, "売上登録待ち"
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
      post aicoo_daily_runs_url, params: { aicoo_daily_run: { target_date: Date.yesterday.to_s } }
    end

    assert_redirected_to aicoo_daily_run_url(daily_run)
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

require "test_helper"

class AicooDailyRunsControllerTest < ActionDispatch::IntegrationTest
  test "shows daily run index" do
    AicooDailyRun.create!(target_date: Date.yesterday, status: "succeeded", started_at: Time.current)

    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "AICOO Daily Run"
    assert_includes response.body, "実行履歴"
  end

  test "shows daily run detail" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "succeeded", run_log: "done")

    get aicoo_daily_run_url(daily_run)

    assert_response :success
    assert_includes response.body, "AICOO Daily Run詳細"
    assert_includes response.body, "補正できない理由"
    assert_includes response.body, "BusinessMetricDaily不足"
    assert_includes response.body, "done"
  end

  test "creates daily run from form" do
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "succeeded")

    with_daily_runner_stub(->(target_date:) { daily_run }) do
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

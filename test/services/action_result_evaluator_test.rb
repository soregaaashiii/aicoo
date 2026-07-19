require "test_helper"

class ActionResultEvaluatorTest < ActiveSupport::TestCase
  setup do
    @action_candidate = action_candidates(:nagazakicho_article)
    @business = @action_candidate.business
    @executed_on = Date.new(2026, 6, 10)
    @evaluated_on = Date.new(2026, 6, 17)
  end

  test "calculates metric deltas from before and after seven day averages" do
    create_metric_window((@executed_on - 7)...@executed_on, clicks: 10, impressions: 100)
    create_metric_window((@executed_on + 1)..(@executed_on + 7), clicks: 20, impressions: 140)
    result = create_result

    ActionResultEvaluator.new(result).call

    result.reload
    assert_equal "evaluated", result.evaluation_status
    assert_equal 10, result.actual_clicks_delta
    assert_equal 40, result.actual_impressions_delta
    assert_operator result.actual_proxy_score_delta, :>, 0
  end

  test "calculates actual revenue and profit from revenue events" do
    create_metric_window((@executed_on - 7)...@executed_on, clicks: 10)
    create_metric_window((@executed_on + 1)..(@executed_on + 7), clicks: 20)
    @business.revenue_events.create!(occurred_on: @executed_on + 2, event_type: "revenue", amount: 12_000)
    @business.revenue_events.create!(occurred_on: @executed_on + 3, event_type: "expense", amount: 2_000)
    result = create_result

    ActionResultEvaluator.new(result).call

    result.reload
    assert_equal 12_000, result.actual_revenue_yen
    assert_equal 10_000, result.actual_profit_yen
    assert_equal 20_000, result.prediction_error_yen
  end

  test "skips safely when metric data is missing" do
    result = create_result

    ActionResultEvaluator.new(result).call

    result.reload
    assert_equal "skipped", result.evaluation_status
    assert_match(/BusinessMetricDailyが不足/, result.note)
  end

  test "evaluates recorded manual actuals when metric data is missing" do
    result = create_result(
      actual_revenue_yen: 8_000,
      actual_profit_yen: 5_500,
      metadata: { "manual_actuals_recorded" => true }
    )

    ActionResultEvaluator.new(result).call

    result.reload
    assert_equal "evaluated", result.evaluation_status
    assert_equal 8_000, result.actual_revenue_yen
    assert_equal 5_500, result.actual_profit_yen
    assert_match(/登録済み実績値で評価/, result.note)
  end

  test "refreshes expected value learning after evaluation" do
    create_metric_window((@executed_on - 7)...@executed_on, clicks: 10)
    create_metric_window((@executed_on + 1)..(@executed_on + 7), clicks: 20)
    result = create_result
    calls = []

    Aicoo::ExpectedValueLearningRefresh.stub(:refresh_after_action_result!, ->(action_result, source:) { calls << [ action_result, source ] }) do
      ActionResultEvaluator.new(result).call
    end

    assert_equal [ [ result, "action_result_evaluator" ] ], calls
  end

  test "does not refresh expected value learning when skipped" do
    result = create_result
    calls = []

    Aicoo::ExpectedValueLearningRefresh.stub(:refresh_after_action_result!, ->(action_result, source:) { calls << [ action_result, source ] }) do
      ActionResultEvaluator.new(result).call
    end

    assert_empty calls
  end

  private

  def create_result(**attributes)
    ActionResult.create!(
      {
        action_candidate: @action_candidate,
        business: @business,
        executed_on: @executed_on,
        evaluated_on: @evaluated_on
      }.merge(attributes)
    )
  end

  def create_metric_window(range, **attributes)
    range.each do |date|
      @business.business_metric_dailies.create!(
        { recorded_on: date }.merge(attributes)
      )
    end
  end
end

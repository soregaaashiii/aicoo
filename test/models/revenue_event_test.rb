require "test_helper"

class RevenueEventTest < ActiveSupport::TestCase
  test "requires positive amount" do
    event = RevenueEvent.new(
      business: businesses(:suelog),
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 0
    )

    assert_not event.valid?
  end

  test "business calculates monthly and cumulative profit" do
    business = businesses(:suelog)
    business.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 10_000)
    business.revenue_events.create!(occurred_on: Date.current, event_type: "expense", amount: 3_000)
    business.revenue_events.create!(occurred_on: 2.months.ago.to_date, event_type: "revenue", amount: 5_000)

    assert_equal 10_000, business.current_month_revenue
    assert_equal 3_000, business.current_month_expense
    assert_equal 7_000, business.current_month_profit
    assert_equal 15_000, business.cumulative_revenue
    assert_equal 3_000, business.cumulative_expense
    assert_equal 12_000, business.cumulative_profit
  end

  test "completes action candidate from action result" do
    action_candidate = action_candidates(:nagazakicho_article)
    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )
    log = ActionExecutionLog.create!(
      action_candidate:,
      business: action_candidate.business,
      action_result: result,
      planned_action: "10件実行",
      planned_quantity: 10,
      actual_action: "10件実行",
      actual_quantity: 10,
      status: "completed"
    )

    event = RevenueEvent.create!(
      action_result: result,
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 1_000
    )

    assert_equal action_candidate, event.action_candidate
    assert_equal log, event.action_execution_log
    assert_equal action_candidate.business, event.business
  end

  test "completes action candidate and action result from action execution log" do
    action_candidate = action_candidates(:nagazakicho_article)
    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )
    log = ActionExecutionLog.create!(
      action_candidate:,
      business: action_candidate.business,
      action_result: result,
      planned_action: "10件実行",
      planned_quantity: 10,
      actual_action: "10件実行",
      actual_quantity: 10,
      status: "completed"
    )

    event = RevenueEvent.create!(
      action_execution_log: log,
      occurred_on: Date.current,
      event_type: "expense",
      amount: 500
    )

    assert_equal action_candidate, event.action_candidate
    assert_equal result, event.action_result
    assert_equal action_candidate.business, event.business
  end

  test "can link directly to action candidate" do
    action_candidate = action_candidates(:nagazakicho_article)

    event = RevenueEvent.create!(
      action_candidate:,
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 2_000
    )

    assert_equal action_candidate.business, event.business
    assert_equal action_candidate, event.action_candidate
    assert_nil event.action_result
  end
end

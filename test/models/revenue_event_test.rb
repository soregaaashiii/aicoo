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
end

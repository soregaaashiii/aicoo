require "test_helper"

class BusinessAnalyticsHelperTest < ActionView::TestCase
  test "formats chart values for axes and tooltips" do
    assert_equal "データ不足", business_chart_value_label(nil)
    assert_equal "1,234", business_chart_value_label(1234)
    assert_equal "12.35", business_chart_value_label(12.345)
    assert_equal "0.1235", business_chart_value_label(0.12345)
    assert_equal "0", business_chart_value_label(0)
  end

  test "keeps chart scaling based on the existing series maximum" do
    point = Struct.new(:values)
    series = [ point.new({ "clicks" => 10 }), point.new({ "clicks" => 20 }) ]

    assert_equal 20.to_d, business_chart_max(series, "clicks")
    assert_equal 50, business_chart_height(series.first, "clicks", 20)
    assert_equal 100, business_chart_height(series.last, "clicks", 20)
  end

  test "automatically scales ctr to its observed range with headroom" do
    point = Struct.new(:values)
    series = [ point.new({ "ctr" => 0.008 }), point.new({ "ctr" => 0.012 }) ]
    max_value = business_chart_max(series, "ctr")

    assert_equal 0.0132.to_d, max_value
    assert_equal 61, business_chart_height(series.first, "ctr", max_value)
    assert_equal 91, business_chart_height(series.last, "ctr", max_value)
  end

  test "formats ctr axes and tooltips as percentages" do
    assert_equal "1.23%", business_chart_value_label(0.0123, metric: "ctr")
    assert_equal "0.04%", business_chart_value_label(0.0004, metric: "ctr")
    assert_equal "0%", business_chart_value_label(0, metric: "ctr")
  end

  test "renders y axis values and a dated value tooltip for each bar" do
    point = Struct.new(:date, :values)
    series = [
      point.new(Date.new(2026, 10, 18), { "clicks" => 10 }),
      point.new(Date.new(2026, 10, 19), { "clicks" => 20 })
    ]

    render partial: "businesses/analytics_chart", locals: {
      title: "GSCグラフ",
      series:,
      metrics: [ { key: "clicks", label: "clicks" } ]
    }

    assert_select ".business-analytics-y-axis span", text: "20", count: 1
    assert_select ".business-analytics-y-axis span", text: "10", count: 1
    assert_select ".business-analytics-y-axis span", text: "0", count: 1
    assert_select ".business-analytics-bar[data-tooltip='2026-10-19 / clicks: 20']", count: 1
    assert_select ".business-analytics-bar[aria-label='2026-10-18 / clicks: 10'][tabindex='0']", count: 1
  end

  test "renders ctr with an automatic percentage axis and percentage tooltips" do
    point = Struct.new(:date, :values)
    series = [
      point.new(Date.new(2026, 10, 18), { "ctr" => 0.01 }),
      point.new(Date.new(2026, 10, 19), { "ctr" => 0.02 })
    ]

    render partial: "businesses/analytics_chart", locals: {
      title: "GSCグラフ",
      series:,
      metrics: [ { key: "ctr", label: "CTR" } ]
    }

    assert_select ".business-analytics-y-axis span", text: "2.2%", count: 1
    assert_select ".business-analytics-y-axis span", text: "1.1%", count: 1
    assert_select ".business-analytics-y-axis span", text: "0%", count: 1
    assert_select ".business-analytics-bar[data-tooltip='2026-10-19 / CTR: 2%']", count: 1
  end
end

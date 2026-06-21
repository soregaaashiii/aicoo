require "test_helper"

class BusinessMetricDailyTest < ActiveSupport::TestCase
  test "calculates proxy score from daily metrics" do
    metric = BusinessMetricDaily.new(
      business: businesses(:suelog),
      recorded_on: Date.current,
      impressions: 1_000,
      clicks: 20,
      sessions: 30,
      pageviews: 40,
      phone_clicks: 2,
      map_clicks: 3,
      affiliate_clicks: 4
    )

    assert_equal 204.0, metric.proxy_score
  end

  test "proxy score uses business weight before global weight" do
    business = businesses(:suelog)
    ProxyScoreWeight.create!(clicks_weight: 2, source_type: "global_test")
    ProxyScoreWeight.create!(business:, clicks_weight: 3, source_type: "business_test")
    metric = BusinessMetricDaily.new(business:, recorded_on: Date.current, clicks: 10)

    assert_equal 30.0, metric.proxy_score
  end

  test "proxy score uses global weight when business weight is missing" do
    business = businesses(:suelog)
    ProxyScoreWeight.create!(clicks_weight: 2, source_type: "global_test")
    metric = BusinessMetricDaily.new(business:, recorded_on: Date.current, clicks: 10)

    assert_equal 20.0, metric.proxy_score
  end

  test "proxy score falls back to fixed defaults when no saved weight exists" do
    metric = BusinessMetricDaily.new(business: businesses(:suelog), recorded_on: Date.current, clicks: 10)

    assert_equal 10.0, metric.proxy_score
  end

  test "business calculates monthly and cumulative proxy score" do
    business = businesses(:suelog)
    business.business_metric_dailies.create!(
      recorded_on: Date.current,
      impressions: 1_000,
      clicks: 10,
      sessions: 10,
      pageviews: 10,
      phone_clicks: 1,
      map_clicks: 1,
      affiliate_clicks: 1
    )
    business.business_metric_dailies.create!(
      recorded_on: 2.months.ago.to_date,
      impressions: 500,
      clicks: 5
    )

    assert_equal 73.0, business.current_month_proxy_score
    assert_equal 83.0, business.cumulative_proxy_score
  end

  test "business calculates recent proxy score windows" do
    business = businesses(:suelog)
    business.business_metric_dailies.create!(recorded_on: Date.current, clicks: 10)
    business.business_metric_dailies.create!(recorded_on: 6.days.ago.to_date, clicks: 20)
    business.business_metric_dailies.create!(recorded_on: 20.days.ago.to_date, clicks: 30)
    business.business_metric_dailies.create!(recorded_on: 40.days.ago.to_date, clicks: 40)

    assert_equal 30.0, business.recent_7d_proxy_score
    assert_equal 60.0, business.recent_30d_proxy_score
  end

  test "metrics cannot be negative" do
    metric = BusinessMetricDaily.new(
      business: businesses(:suelog),
      recorded_on: Date.current,
      clicks: -1
    )

    assert_not metric.valid?
  end
end

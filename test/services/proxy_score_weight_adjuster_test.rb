require "test_helper"

class ProxyScoreWeightAdjusterTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @adjuster = ProxyScoreWeightAdjuster.new
  end

  test "does not change weights and writes log when sample size is too small" do
    log = @adjuster.adjust_business!(business: @business, start_date: Date.current - 30, end_date: Date.current)
    weight = log.proxy_score_weight

    assert_equal "sample size too small", log.reason
    assert_equal weight.weights_hash.stringify_keys.transform_values(&:to_s), log.before_weights
    assert_equal log.before_weights, log.after_weights
    assert_equal 0, log.adjustment_rate
  end

  test "increases metrics that were positive before revenue event" do
    create_metric_days(@business, start_date: Date.new(2026, 1, 1), days: 30, clicks: 1)
    @business.revenue_events.create!(occurred_on: Date.new(2026, 1, 31), event_type: "revenue", amount: 1_000)

    log = @adjuster.adjust_business!(business: @business, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31))
    weight = log.proxy_score_weight

    assert_match(/adjusted because revenue followed proxy growth/, log.reason)
    assert_operator weight.clicks_weight, :>, ProxyScoreWeight::DEFAULT_WEIGHTS.fetch(:clicks_weight)
    assert_operator weight.clicks_weight, :<=, ProxyScoreWeight::DEFAULT_WEIGHTS.fetch(:clicks_weight) * 1.01
    assert_operator log.adjustment_rate, :<, 0.01
  end

  test "reduces shallow metrics when proxy grew without revenue" do
    create_metric_days(@business, start_date: Date.new(2026, 2, 1), days: 30, impressions: 100, sessions: 5, pageviews: 10)

    log = @adjuster.adjust_business!(business: @business, start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 3, 2))
    weight = log.proxy_score_weight

    assert_equal "reduced shallow metrics because proxy grew without revenue", log.reason
    assert_operator weight.impressions_weight, :<, ProxyScoreWeight::DEFAULT_WEIGHTS.fetch(:impressions_weight)
    assert_operator weight.sessions_weight, :<, ProxyScoreWeight::DEFAULT_WEIGHTS.fetch(:sessions_weight)
    assert_equal ProxyScoreWeight::DEFAULT_WEIGHTS.fetch(:phone_clicks_weight).to_d, weight.phone_clicks_weight.to_d
  end

  test "confidence score controls adjustment rate" do
    create_metric_days(@business, start_date: Date.new(2026, 1, 1), days: 30, clicks: 1)
    @business.revenue_events.create!(occurred_on: Date.new(2026, 1, 31), event_type: "revenue", amount: 1_000)

    log = @adjuster.adjust_business!(business: @business, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31))

    assert_equal 21, log.confidence_score
    assert_equal "0.0021".to_d, log.adjustment_rate
  end

  test "weights stay inside safety range" do
    create_metric_days(@business, start_date: Date.new(2026, 4, 1), days: 30, affiliate_clicks: 1)
    @business.revenue_events.create!(occurred_on: Date.new(2026, 5, 1), event_type: "revenue", amount: 1_000)
    ProxyScoreWeight.create!(business: @business, affiliate_clicks_weight: 200)

    @adjuster.adjust_business!(business: @business, start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 5, 1))

    assert_equal 200.to_d, @business.reload.current_proxy_score_weight.affiliate_clicks_weight
  end

  test "global weight is not changed when global sample condition is missing" do
    log = @adjuster.adjust_global!(start_date: Date.current - 30, end_date: Date.current)

    assert_match(/skipped global adjustment/, log.reason)
    assert_equal 0, log.adjustment_rate
    assert_equal log.before_weights, log.after_weights
  end

  private

  def create_metric_days(business, start_date:, days:, **metrics)
    days.times do |offset|
      business.business_metric_dailies.create!(
        { recorded_on: start_date + offset }.merge(metrics)
      )
    end
  end
end

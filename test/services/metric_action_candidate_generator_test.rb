require "test_helper"

class MetricActionCandidateGeneratorTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @today = Date.new(2026, 6, 21)
  end

  test "creates reinforcement candidate when proxy score is rising" do
    create_metric_series(default_clicks: 5, recent_clicks: 20)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("伸びている代理指標を強化") }
    candidate = result.created.find { |record| record.title.include?("伸びている代理指標を強化") }
    assert_equal "ai_business", candidate.generation_source
    assert_equal "proxy_growth_reinforce", candidate.metadata.fetch("metric_rule")
    assert_match(/metric_rule:proxy_growth_reinforce/, candidate.evaluation_reason)
  end

  test "creates improvement candidate when proxy score is falling" do
    create_metric_series(default_clicks: 20, recent_clicks: 2)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("代理指標低下原因") }
  end

  test "creates ctr improvement candidate when impressions rise but clicks stall" do
    create_metric_series(default_impressions: 10, recent_impressions: 100, default_clicks: 5, recent_clicks: 5)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("CTR改善") }
  end

  test "creates conversion path candidate when clicks exist but cv clicks are missing" do
    create_metric_series(default_clicks: 5, recent_clicks: 10)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("CV導線") }
  end

  test "creates revenue expansion candidate when revenue exists" do
    create_metric_series(default_clicks: 5, recent_clicks: 10)
    @business.revenue_events.create!(occurred_on: @today - 1, event_type: "revenue", amount: 10_000)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("収益発生施策を横展開") }
  end

  test "creates pause or withdraw candidate when no revenue and proxy score is falling" do
    create_metric_series(default_clicks: 20, recent_clicks: 1)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.action_type == "withdraw" }
  end

  test "does not create duplicate candidate when similar one exists within 7 days" do
    create_metric_series(default_impressions: 10, recent_impressions: 100, default_clicks: 5, recent_clicks: 5)
    @business.action_candidates.create!(
      title: "#{@business.name}のCTR改善を行う",
      action_type: "seo_improvement",
      generation_source: "ai_business",
      evaluation_reason: "metric_rule:ctr_improvement",
      created_at: @today.to_time
    )

    MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert_equal 1, @business.action_candidates.where(title: "#{@business.name}のCTR改善を行う").count
  end

  test "skips when metric data is insufficient" do
    3.times do |offset|
      @business.business_metric_dailies.create!(recorded_on: @today - offset, clicks: 10)
    end

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert_empty result.created
    assert_includes result.skipped.first, "データ不足"
  end

  private

  def create_metric_series(default_clicks: 0, recent_clicks: nil, default_impressions: 0, recent_impressions: nil)
    recent_clicks = default_clicks if recent_clicks.nil?
    recent_impressions = default_impressions if recent_impressions.nil?

    30.times do |offset|
      date = @today - 29 + offset
      recent = date >= @today - 6
      @business.business_metric_dailies.create!(
        recorded_on: date,
        impressions: recent ? recent_impressions : default_impressions,
        clicks: recent ? recent_clicks : default_clicks,
        sessions: recent ? 10 : 10,
        pageviews: recent ? 10 : 10
      )
    end
  end
end

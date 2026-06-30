require "test_helper"

class MetricActionCandidateGeneratorTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @today = Date.new(2026, 6, 21)
    DataSourceCostProfile.ensure_defaults!
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: nil)
  end

  test "creates reinforcement candidate when proxy score is rising" do
    create_metric_series(default_clicks: 5, recent_clicks: 20)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.title.include?("伸びている代理指標を強化") }
    candidate = result.created.find { |record| record.title.include?("伸びている代理指標を強化") }
    assert_equal "ai_business", candidate.generation_source
    assert_equal "proxy_growth_reinforce", candidate.metadata.fetch("metric_rule")
    assert_equal "internal_only", candidate.metadata.fetch("data_mode")
    assert_equal [ "serp" ], candidate.metadata.fetch("missing_sources")
    assert_equal true, candidate.metadata.fetch("confidence_penalty")
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

  test "creates engagement improvement candidates from weak GA4 engagement" do
    create_metric_series(
      default_clicks: 5,
      recent_clicks: 8,
      default_sessions: 20,
      recent_sessions: 20,
      default_pageviews: 50,
      recent_pageviews: 22,
      default_engagement_time: 180,
      recent_engagement_time: 45,
      recent_bounce_rate: 0.82,
      recent_conversions: 0
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.any? { |candidate| candidate.metadata.fetch("metric_rule") == "engagement_time_improvement" }
    assert result.created.any? { |candidate| candidate.metadata.fetch("metric_rule") == "engagement_navigation_improvement" }
    assert result.created.any? { |candidate| candidate.metadata.fetch("metric_rule") == "engagement_exit_path_improvement" }
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

  def create_metric_series(default_clicks: 0, recent_clicks: nil, default_impressions: 0, recent_impressions: nil,
                           default_sessions: 10, recent_sessions: nil, default_pageviews: 10, recent_pageviews: nil,
                           default_engagement_time: 120, recent_engagement_time: nil, default_bounce_rate: 0.3,
                           recent_bounce_rate: nil, default_conversions: 1, recent_conversions: nil)
    recent_clicks = default_clicks if recent_clicks.nil?
    recent_impressions = default_impressions if recent_impressions.nil?
    recent_sessions = default_sessions if recent_sessions.nil?
    recent_pageviews = default_pageviews if recent_pageviews.nil?
    recent_engagement_time = default_engagement_time if recent_engagement_time.nil?
    recent_bounce_rate = default_bounce_rate if recent_bounce_rate.nil?
    recent_conversions = default_conversions if recent_conversions.nil?

    30.times do |offset|
      date = @today - 29 + offset
      recent = date >= @today - 6
      @business.business_metric_dailies.create!(
        recorded_on: date,
        impressions: recent ? recent_impressions : default_impressions,
        clicks: recent ? recent_clicks : default_clicks,
        sessions: recent ? recent_sessions : default_sessions,
        pageviews: recent ? recent_pageviews : default_pageviews,
        average_engagement_time_seconds: recent ? recent_engagement_time : default_engagement_time,
        bounce_rate: recent ? recent_bounce_rate : default_bounce_rate,
        engagement_rate: recent ? 0.3 : 0.6,
        conversions: recent ? recent_conversions : default_conversions
      )
    end
  end
end

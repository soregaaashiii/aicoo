require "test_helper"

module Aicoo
  class BusinessAnalyticsSummaryTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.business_metric_dailies.create!(
        recorded_on: Date.current,
        impressions: 1_000,
        clicks: 50,
        sessions: 200,
        pageviews: 500,
        users: 120,
        views_per_user: 4.1,
        average_engagement_time_seconds: 96,
        engagement_rate: 0.62,
        bounce_rate: 0.31,
        conversions: 8,
        event_count: 900,
        scroll_events: 140,
        internal_search_events: 3,
        affiliate_clicks: 12,
        phone_clicks: 4,
        map_clicks: 8
      )
      @business.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 30_000)
      @candidate = @business.action_candidates.create!(
        title: "Analytics summary candidate",
        action_type: "seo_improvement",
        status: "approved",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 2,
        practicality_score: 80,
        metadata: { "evidence" => { "score" => "70" } }
      )
      @candidate.create_action_result!(
        business: @business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        actual_revenue_yen: 40_000,
        actual_profit_yen: 25_000
      )
      OwnerDecisionLog.record!(
        subject: @candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )
      @business.analysis_candidates.create!(
        analysis_source: "serp",
        expected_value_yen: 1_500,
        estimated_cost_yen: 20,
        estimated_minutes: 30,
        roi: 75,
        confidence: 60,
        priority: 90,
        execution_mode: "manual",
        reason: "順位急落を確認するためSERP分析を推奨",
        due_on: Date.current
      )
    end

    test "summarizes business analytics periods and chart series" do
      result = BusinessAnalyticsSummary.new(@business).call

      assert_equal @business, result.business
      assert_equal 50, result.periods.fetch(7).gsc_clicks
      assert_equal 1_000, result.periods.fetch(30).gsc_impressions
      assert_equal 200, result.periods.fetch(7).ga4_sessions
      assert_equal 96, result.periods.fetch(7).average_engagement_time_seconds
      assert_equal 2.5.to_d, result.periods.fetch(7).views_per_session
      assert_equal 0.04.to_d, result.periods.fetch(7).conversion_rate
      assert_equal 30_000, result.periods.fetch(30).revenue_yen
      assert_equal Date.current, result.gsc_series.last.date
      assert_equal 50, result.gsc_series.last.values["clicks"]
      assert_equal 200, result.ga4_series.last.values["sessions"]
      assert_equal 8, result.ga4_series.last.values["conversions"]
      assert_equal 96, result.engagement_series.last.values["average_engagement_time_seconds"]
      assert_equal 2.5.to_d, result.engagement_series.last.values["views_per_session"]
      assert_equal 30_000, result.revenue_series.last.values["revenue_yen"]
      assert_operator result.action_series.last.values["action_candidates"], :>=, 1
      assert_equal 1, result.learning_series.last.values["decision_logs"]
      assert result.data_status[:has_gsc_data]
      assert result.data_status[:has_ga4_data]
      assert result.data_status[:has_engagement_data]
      assert result.data_status[:has_revenue_data]
      assert result.cost_estimates.find { |estimate| estimate.source_key == "serp" }.manual?
      assert_equal "serp", result.analysis_candidates.first.analysis_source
    end

    test "returns safe empty state when analytics data is missing" do
      business = businesses(:cards)
      result = BusinessAnalyticsSummary.new(business).call

      assert_equal 0, result.periods.fetch(7).gsc_clicks
      assert_equal 0, result.periods.fetch(30).ga4_sessions
      assert_equal 0, result.periods.fetch(30).revenue_yen
      assert_not result.data_status[:has_gsc_data]
      assert_not result.data_status[:has_ga4_data]
      assert_not result.data_status[:has_engagement_data]
      assert_not result.data_status[:has_revenue_data]
    end
  end
end

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
    end

    test "summarizes business analytics periods and chart series" do
      result = BusinessAnalyticsSummary.new(@business).call

      assert_equal @business, result.business
      assert_equal 50, result.periods.fetch(7).gsc_clicks
      assert_equal 1_000, result.periods.fetch(30).gsc_impressions
      assert_equal 200, result.periods.fetch(7).ga4_sessions
      assert_equal 30_000, result.periods.fetch(30).revenue_yen
      assert_equal Date.current, result.gsc_series.last.date
      assert_equal 50, result.gsc_series.last.values["clicks"]
      assert_equal 200, result.ga4_series.last.values["sessions"]
      assert_equal 30_000, result.revenue_series.last.values["revenue_yen"]
      assert_operator result.action_series.last.values["action_candidates"], :>=, 1
      assert_equal 1, result.learning_series.last.values["decision_logs"]
      assert result.data_status[:has_gsc_data]
      assert result.data_status[:has_ga4_data]
      assert result.data_status[:has_revenue_data]
      assert result.cost_estimates.find { |estimate| estimate.source_key == "serp" }.manual?
    end

    test "returns safe empty state when analytics data is missing" do
      business = businesses(:cards)
      result = BusinessAnalyticsSummary.new(business).call

      assert_equal 0, result.periods.fetch(7).gsc_clicks
      assert_equal 0, result.periods.fetch(30).ga4_sessions
      assert_equal 0, result.periods.fetch(30).revenue_yen
      assert_not result.data_status[:has_gsc_data]
      assert_not result.data_status[:has_ga4_data]
      assert_not result.data_status[:has_revenue_data]
    end
  end
end

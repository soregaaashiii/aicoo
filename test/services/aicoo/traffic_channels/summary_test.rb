require "test_helper"

module Aicoo
  module TrafficChannels
    class SummaryTest < ActiveSupport::TestCase
      test "summarizes today's traffic channel results" do
        TrafficChannelRun.create!(
          business: businesses(:suelog),
          channel_key: "serp",
          status: "success",
          ran_at: Time.current,
          sessions: 10,
          clicks: 4,
          conversions: 1,
          revenue_yen: 2000,
          cost_yen: 500,
          hours_spent: 0.5
        )
        ActionCandidate.create!(
          business: businesses(:suelog),
          title: "Traffic改善",
          action_type: "market_research",
          generation_source: "traffic_channel",
          status: "idea",
          immediate_value_yen: 1000,
          success_probability: 0.3,
          expected_hours: 1
        )

        summary = Summary.call

        assert_equal "Healthy", summary.health
        assert_operator summary.enabled_channel_count, :>=, 1
        assert_equal 1, summary.today_active_channel_count
        assert_equal 10, summary.today_total_inflow_count
        assert_equal 1, summary.today_conversion_count
        assert_equal 2000, summary.today_revenue_yen
        assert_equal 1, summary.today_traffic_action_candidate_count
        assert_equal "SERP", summary.best_channel.label
      end
    end
  end
end

require "test_helper"

module Aicoo
  class EngagementSummaryTest < ActiveSupport::TestCase
    test "summarizes engagement by business and task rows" do
      business = businesses(:suelog)
      business.business_metric_dailies.create!(
        recorded_on: Date.current,
        sessions: 100,
        pageviews: 250,
        average_engagement_time_seconds: 120,
        engagement_rate: 0.6,
        conversions: 5,
        scroll_events: 40
      )
      BusinessPlaybook.create!(
        business:,
        sample_count: 3,
        confidence_score: 60,
        metadata: {
          "task_summary" => {
            "内部リンク追加" => {
              "task" => "内部リンク追加",
              "score" => "80",
              "average_engagement_delta" => "12",
              "average_navigation_delta" => "0.4",
              "average_conversion_delta" => "0.02",
              "success_rate" => "0.7",
              "sample_count" => "3"
            }
          }
        }
      )

      result = EngagementSummary.new.call

      row = result.business_rows.find { |item| item.business == business }
      assert_equal 100, row.sessions
      assert_equal 120, row.average_engagement_time_seconds
      assert_equal 2.5.to_d, row.views_per_session
      assert result.average_engagement_score.positive?
      assert result.task_rows.any? { |task| task["task"] == "内部リンク追加" && task["average_engagement_delta"] == "12" }
    end
  end
end

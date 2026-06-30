require "test_helper"

module Aicoo
  class ActivityEvaluationBuilderTest < ActiveSupport::TestCase
    test "evaluates activity log against business metrics and revenue" do
      business = businesses(:suelog)
      occurred_at = 10.days.ago
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "1",
        title: "記事更新",
        occurred_at:,
        detected_at: occurred_at,
        idempotency_key: "article-1-updated"
      )
      create_metrics(business, (occurred_at.to_date - 7.days)...occurred_at.to_date, clicks: 10, sessions: 20)
      create_metrics(business, (occurred_at.to_date + 1.day)..(occurred_at.to_date + 7.days), clicks: 30, sessions: 60)
      RevenueEvent.create!(business:, event_type: "revenue", amount: 1000, occurred_on: occurred_at.to_date + 2.days)

      result = ActivityEvaluationBuilder.new.call

      assert_operator result.evaluated_count, :>=, 1
      evaluation = activity_log.activity_evaluations.find_by!(evaluation_window_days: 7)
      assert_equal "evaluated", evaluation.status
      assert_equal 1000.0, evaluation.result_snapshot["revenue_yen"]
      assert_equal "evaluated", activity_log.reload.evaluation_status
    end

    private

    def create_metrics(business, range, clicks:, sessions:)
      range.each do |date|
        BusinessMetricDaily.create!(
          business:,
          recorded_on: date,
          impressions: clicks * 10,
          clicks:,
          sessions:,
          pageviews: sessions * 2
        )
      end
    end
  end
end

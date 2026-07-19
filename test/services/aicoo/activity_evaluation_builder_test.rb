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

    test "evaluates suelog shop activity with resource level shop clicks" do
      business = businesses(:suelog)
      occurred_at = 10.days.ago
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "smoking_verified",
        resource_type: "Shop",
        resource_id: "123",
        title: "喫煙確認",
        occurred_at:,
        detected_at: occurred_at,
        idempotency_key: "shop-123-smoking-verified",
        metadata: {
          "shop_id" => "123",
          "verified" => true,
          "smoking_area" => 1,
          "smoking_type" => 0
        }
      )
      builder = ActivityEvaluationBuilder.new

      builder.stub(:suelog_shop_click_snapshot, lambda { |_log, range|
        count = range.exclude_end? ? 2.0 : 9.0
        {
          "resource_metric_source" => "suelog_shop_clicks",
          "resource_type" => "Shop",
          "resource_id" => "123",
          "shop_clicks" => count
        }
      }) do
        result = builder.call
        assert_operator result.evaluated_count, :>=, 1
      end

      evaluation = activity_log.activity_evaluations.find_by!(evaluation_window_days: 7)
      assert_equal "evaluated", evaluation.status
      assert_equal 2.0, evaluation.baseline_snapshot["shop_clicks"]
      assert_equal 9.0, evaluation.result_snapshot["shop_clicks"]
      assert_equal 7.0, evaluation.metric_deltas["shop_clicks"]["delta"]
      assert_equal "evaluated", activity_log.reload.evaluation_status
    end

    test "creates evaluated action result from evaluated activity without manual actuals" do
      business = businesses(:suelog)
      candidate = action_candidates(:nagazakicho_article)
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
        idempotency_key: "article-1-updated-auto-result",
        metadata: { "action_candidate_id" => candidate.id }
      )
      create_metrics(business, (occurred_at.to_date - 7.days)...occurred_at.to_date, clicks: 10, sessions: 20)
      create_metrics(business, (occurred_at.to_date + 1.day)..(occurred_at.to_date + 7.days), clicks: 30, sessions: 60)
      RevenueEvent.create!(business:, event_type: "revenue", amount: 1000, occurred_on: occurred_at.to_date + 2.days)

      refresh_calls = []
      Aicoo::ExpectedValueLearningRefresh.stub(:refresh_after_action_result!, ->(action_result, source:) { refresh_calls << [ action_result, source ] }) do
        result = ActivityEvaluationBuilder.new.call
        assert_operator result.action_results_generated_count, :>=, 1
      end

      action_result = candidate.reload.action_result
      assert_equal "evaluated", action_result.evaluation_status
      assert_equal false, action_result.manual_actuals_recorded?
      assert_equal true, action_result.metadata.dig("activity_learning_pipeline", "auto_generated")
      assert_equal activity_log.id, action_result.metadata.dig("activity_learning_pipeline", "business_activity_log_id")
      assert_operator action_result.actual_clicks_delta, :>, 0
      assert_equal [ [ action_result, "activity_learning_pipeline" ] ], refresh_calls
    end

    test "records skipped reason when activity cannot be linked to action candidate" do
      business = businesses(:suelog)
      occurred_at = 10.days.ago
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "missing",
        title: "記事更新",
        occurred_at:,
        detected_at: occurred_at,
        idempotency_key: "article-missing-updated"
      )
      evaluation = ActivityEvaluation.create!(
        business:,
        business_activity_log: activity_log,
        evaluation_window_days: 7,
        status: "evaluated",
        evaluated_at: Time.current,
        baseline_snapshot: { "clicks" => 1 },
        result_snapshot: { "clicks" => 2 },
        metric_deltas: { "clicks" => { "before" => 1, "after" => 2, "delta" => 1 } }
      )

      result = ActivityActionResultBridge.call(evaluation)

      assert_equal "skipped", result.status
      assert_equal "action_candidate_not_found", result.reason
      assert_equal "skipped", evaluation.reload.metadata.dig("action_result_bridge", "status")
      assert_equal "action_candidate_not_found", evaluation.metadata.dig("action_result_bridge", "reason")
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

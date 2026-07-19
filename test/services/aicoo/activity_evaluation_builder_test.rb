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
      assert_equal 0.1, evaluation.result_snapshot["ctr"]
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

    test "records independent learning when activity has no explicit action candidate" do
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
      assert_equal "independent_activity_without_candidate", result.reason
      assert_equal "skipped", evaluation.reload.metadata.dig("action_result_bridge", "status")
      assert_equal "independent_activity_without_candidate", evaluation.metadata.dig("action_result_bridge", "reason")
    end

    test "does not infer action candidate learning from a matching resource alone" do
      business = businesses(:suelog)
      candidate = action_candidates(:nagazakicho_article)
      candidate.update!(metadata: candidate.metadata.to_h.merge("article_id" => "resource-only"))
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "resource-only",
        title: "候補外の記事更新",
        occurred_at: 10.days.ago,
        detected_at: 10.days.ago,
        idempotency_key: "resource-only-independent"
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

      assert_no_difference("ActionResult.count") do
        result = ActivityActionResultBridge.call(evaluation)
        assert_equal "independent_activity_without_candidate", result.reason
      end
    end

    test "registers pending independent activity learning with aggregated context" do
      business = businesses(:suelog)
      occurred_at = 1.hour.ago
      two_logs = [ "shop-a", "shop-b" ].map do |resource_id|
        BusinessActivityLog.create!(
          business:,
          source_app: "suelog",
          activity_type: "shop_created",
          resource_type: "Shop",
          resource_id:,
          title: "店舗追加",
          occurred_at:,
          detected_at: occurred_at,
          idempotency_key: "#{resource_id}-independent",
          metadata: { "area" => "梅田", "genre" => "居酒屋", "smoking_type" => "喫煙可" }
        )
      end

      ActivityEvaluationBuilder.new.call(business:)

      learning = two_logs.first.activity_evaluations.find_by!(evaluation_window_days: 7).metadata.fetch("independent_activity_learning")
      assert_equal "independent_activity", two_logs.first.activity_evaluations.first.metadata["learning_track"]
      assert_equal 2, learning["shop_count"]
      assert_equal 2, learning["created_count"]
      assert_equal "梅田", learning["area"]
      assert_equal "居酒屋", learning["genre"]
      assert_nil learning["action_candidate_id"]
    end

    test "does not record aicoo internal events as independent learning" do
      business = businesses(:suelog)
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "aicoo",
        activity_type: "landing_page_update",
        resource_type: "AicooLabLandingPage",
        resource_id: "internal-lp",
        title: "LP更新",
        occurred_at: 1.hour.ago,
        detected_at: 1.hour.ago,
        idempotency_key: "internal-lp-independent-learning"
      )

      ActivityEvaluationBuilder.new.call(business:)

      evaluation = activity_log.activity_evaluations.find_by!(evaluation_window_days: 7)
      assert_nil evaluation.metadata["independent_activity_learning"]
      assert_nil evaluation.metadata["learning_track"]
      assert_equal "internal_event", evaluation.metadata.dig("independent_activity_learning_eligibility", "excluded_reason")
      assert_equal true, evaluation.metadata.dig("independent_activity_learning_eligibility", "is_internal_event")
    end

    test "creates pending evaluations immediately before evaluation windows are due" do
      business = businesses(:suelog)
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "recent-article",
        title: "直近の記事更新",
        occurred_at: 1.hour.ago,
        detected_at: 1.hour.ago,
        idempotency_key: "recent-article-updated"
      )

      result = ActivityEvaluationBuilder.new.call(business:)

      assert_equal 3, result.created_count
      assert_equal 3, result.pending_count
      assert_equal ActivityEvaluationBuilder::WINDOWS, activity_log.activity_evaluations.order(:evaluation_window_days).pluck(:evaluation_window_days)
      assert activity_log.activity_evaluations.all?(&:pending?)
      assert_equal "evaluation_window_not_due", activity_log.activity_evaluations.first.metadata.dig("activity_evaluation_builder", "reason")
      assert_equal "pending", activity_log.reload.evaluation_status
    end

    test "continues processing pending windows after an earlier window was evaluated" do
      business = businesses(:suelog)
      occurred_at = 20.days.ago
      activity_log = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "multi-window-article",
        title: "複数期間の記事更新",
        occurred_at:,
        detected_at: occurred_at,
        idempotency_key: "multi-window-article-updated"
      )
      create_metrics(business, (occurred_at.to_date - 7.days)...occurred_at.to_date, clicks: 10, sessions: 20)
      create_metrics(business, (occurred_at.to_date + 1.day)..(occurred_at.to_date + 30.days), clicks: 30, sessions: 60)

      first = ActivityEvaluationBuilder.new.call(business:)
      assert_equal 2, first.evaluated_count
      assert_equal "evaluated", activity_log.reload.evaluation_status
      assert activity_log.activity_evaluations.find_by!(evaluation_window_days: 30).pending?

      second = travel 11.days do
        ActivityEvaluationBuilder.new.call(business:)
      end

      assert_equal 1, second.evaluated_count
      assert activity_log.activity_evaluations.find_by!(evaluation_window_days: 30).evaluated?
    end

    test "continues with later activities when one evaluation fails" do
      business = businesses(:suelog)
      failed_log = create_activity_log(business, "failed-evaluation", 10.days.ago)
      successful_log = create_activity_log(business, "successful-evaluation", 10.days.ago)
      builder = ActivityEvaluationBuilder.new
      snapshots = {
        baseline: { "clicks" => 1.0 },
        result: { "clicks" => 2.0 }
      }

      builder.stub(:snapshots_for, lambda { |activity_log, _window|
        raise "snapshot failure" if activity_log.id == failed_log.id

        snapshots
      }) do
        result = builder.call(business:)
        assert_equal 1, result.failed_count
      end

      assert_match "snapshot failure", failed_log.reload.metadata["evaluation_error"]
      assert successful_log.activity_evaluations.evaluated.exists?
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

    def create_activity_log(business, key, occurred_at)
      BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: key,
        title: key,
        occurred_at:,
        detected_at: occurred_at,
        idempotency_key: key
      )
    end
  end
end

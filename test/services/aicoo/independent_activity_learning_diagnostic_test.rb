require "test_helper"

module Aicoo
  class IndependentActivityLearningDiagnosticTest < ActiveSupport::TestCase
    test "keeps independent activity out of action results and reports evaluation windows" do
      business = businesses(:suelog)
      activity = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "independent-shop",
        title: "独立した店舗追加",
        occurred_at: 10.days.ago,
        detected_at: 10.days.ago,
        idempotency_key: "independent-diagnostic-shop",
        metadata: { "area" => "難波", "genre" => "バー" }
      )
      evaluation = ActivityEvaluation.create!(
        business:,
        business_activity_log: activity,
        evaluation_window_days: 7,
        status: "evaluated",
        evaluated_at: Time.current,
        metric_deltas: { "clicks" => { "delta" => 4 } }
      )
      IndependentActivityLearning.record!(evaluation)

      assert_no_difference([ "ActionResult.count", "ActionCandidate.count" ]) do
        result = IndependentActivityLearningDiagnostic.new(business_id: business.id).call
        row = result.rows.find { |item| item.activity_type == "shop_created" && item.area == "難波" }
        assert row
        assert_equal "バー", row.genre
        assert_equal "suelog", row.source_app
        assert_equal "Shop", row.source_model
        assert_equal "suelog_user_activity", row.included_reason
        assert_equal true, row.is_suelog_activity
        assert_equal false, row.is_internal_event
        assert_equal "evaluated", row.evaluations.dig(7, "status")
        assert_nil evaluation.reload.metadata.dig("independent_activity_learning", "action_candidate_id")
      end
    end

    test "reports internal events as excluded instead of independent learning" do
      business = businesses(:suelog)
      activity = BusinessActivityLog.create!(
        business:,
        source_app: "aicoo",
        activity_type: "action_result_update",
        resource_type: "ActionResult",
        resource_id: "internal-result",
        title: "ActionResult更新",
        occurred_at: 10.days.ago,
        detected_at: 10.days.ago,
        idempotency_key: "internal-action-result-diagnostic"
      )
      evaluation = ActivityEvaluation.create!(
        business:,
        business_activity_log: activity,
        evaluation_window_days: 7,
        status: "evaluated",
        evaluated_at: Time.current
      )

      IndependentActivityLearning.record!(evaluation)
      result = IndependentActivityLearningDiagnostic.new(business_id: business.id).call
      excluded = result.excluded_rows.find { |row| row.activity_log_id == activity.id }

      assert excluded
      assert_equal "internal_event", excluded.excluded_reason
      assert_equal true, excluded.is_internal_event
      assert_equal false, excluded.is_suelog_activity
      assert_not result.rows.any? { |row| row.activity_type == "action_result_update" }
      assert_nil evaluation.reload.metadata["independent_activity_learning"]
    end
  end
end

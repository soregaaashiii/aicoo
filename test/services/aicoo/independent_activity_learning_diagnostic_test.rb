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
        assert_equal "evaluated", row.evaluations.dig(7, "status")
        assert_nil evaluation.reload.metadata.dig("independent_activity_learning", "action_candidate_id")
      end
    end
  end
end

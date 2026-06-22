require "test_helper"

module Owner
  class EvaluatorTrendsControllerTest < ActionDispatch::IntegrationTest
    test "shows evaluator trends" do
      MetaEvaluationSnapshot.create!(
        recorded_on: Date.current,
        evaluator_type: "gsc",
        average_expected_value_yen: 10_000,
        average_confidence_score: 82,
        candidate_count: 3,
        weighted_contribution_score: 8_200,
        note: "gsc snapshot"
      )

      get owner_evaluator_trends_url

      assert_response :success
      assert_includes response.body, "判断材料の推移"
      assert_includes response.body, "検索流入"
      assert_includes response.body, "gsc snapshot"
    end
  end
end

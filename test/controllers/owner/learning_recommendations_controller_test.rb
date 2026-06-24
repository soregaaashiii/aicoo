require "test_helper"

module Owner
  class LearningRecommendationsControllerTest < ActionDispatch::IntegrationTest
    test "creates action candidate from recommendation" do
      assert_difference("ActionCandidate.count", 1) do
        post create_action_candidate_owner_learning_recommendation_url, params: {
          title: "予測利益を保守化する",
          reason: "SEO記事系の予測利益が過大です。",
          recommended_action: "成功確率を見直してください。",
          category: "reduce_overestimation",
          priority: "high"
        }
      end

      candidate = ActionCandidate.order(:created_at).last
      assert_redirected_to action_candidate_url(candidate)
      assert_equal "learning_improvement", candidate.action_type
      assert_equal "learning_report", candidate.generation_source
      assert_equal "lab", candidate.department
      assert_match "成功確率", candidate.evaluation_reason
    end

    test "creates opportunity from recommendation" do
      assert_difference("OpportunityDiscoveryItem.count", 1) do
        post create_opportunity_owner_learning_recommendation_url, params: {
          title: "UI改善が過小評価されている",
          reason: "UI改善の実績が予測より高いです。",
          recommended_action: "類似候補の優先順位を見直してください。",
          category: "review_underestimation",
          priority: "medium"
        }
      end

      opportunity = OpportunityDiscoveryItem.order(:created_at).last
      assert_redirected_to owner_opportunity_url(opportunity)
      assert_equal "learning_report", opportunity.source_type
      assert_equal "new", opportunity.status
      assert_equal 60, opportunity.opportunity_score
    end
  end
end

require "test_helper"

module Owner
  class OpportunitiesControllerTest < ActionDispatch::IntegrationTest
    test "shows opportunities index" do
      OpportunityDiscoveryItem.create!(title: "Index opportunity", business: businesses(:suelog))

      get owner_opportunities_url

      assert_response :success
      assert_includes response.body, "Opportunity Discovery"
      assert_includes response.body, "Discovery Funnel"
      assert_includes response.body, "Opportunity Focus Queue"
      assert_includes response.body, "次にレビューすべきOpportunityを見る"
      assert_includes response.body, "Index opportunity"
    end

    test "creates opportunity" do
      assert_difference("OpportunityDiscoveryItem.count", 1) do
        post owner_opportunities_url, params: {
          opportunity_discovery_item: {
            title: "Owner hypothesis",
            description: "違和感メモ",
            business_id: businesses(:suelog).id,
            source_type: "owner_discovery",
            opportunity_score: 70,
            status: "new"
          }
        }
      end

      assert_redirected_to owner_opportunity_url(OpportunityDiscoveryItem.last)
    end

    test "converts opportunity to candidate" do
      opportunity = OpportunityDiscoveryItem.create!(
        title: "Convert opportunity",
        business: businesses(:suelog),
        opportunity_score: 80
      )

      assert_difference("ActionCandidate.count", 1) do
        assert_difference("OwnerDecisionLog.count", 1) do
          post convert_to_candidate_owner_opportunity_url(opportunity)
        end
      end

      assert_redirected_to action_candidate_url(ActionCandidate.last)
      assert_equal "converted", opportunity.reload.status
      assert_equal "convert", OwnerDecisionLog.last.decision_type
      assert_equal "opportunity_detail", OwnerDecisionLog.last.decision_source
    end

    test "show tracks candidate execution and result" do
      opportunity = OpportunityDiscoveryItem.create!(title: "Tracked opportunity", business: businesses(:suelog))
      candidate = opportunity.convert_to_action_candidate!
      execution = candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
      ActionResult.create!(
        action_execution: execution,
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_profit_yen: 100
      )

      get owner_opportunity_url(opportunity)

      assert_response :success
      assert_includes response.body, "Opportunity Learning"
      assert_includes response.body, "Source Performance"
      assert_includes response.body, "Success"
      assert_includes response.body, "Result"
    end

    test "shows focus queue" do
      OpportunityDiscoveryItem.create!(
        title: "Focus opportunity",
        business: businesses(:suelog),
        opportunity_score: 90
      )

      get focus_owner_opportunities_url

      assert_response :success
      assert_includes response.body, "Opportunity Focus Queue"
      assert_includes response.body, "最優先Opportunity"
      assert_includes response.body, "Focus opportunity"
      assert_includes response.body, "Convert to Candidate"
      assert_includes response.body, "Mark Reviewed"
      assert_includes response.body, "Reject"
    end

    test "focus review marks opportunity reviewed and returns to focus" do
      opportunity = OpportunityDiscoveryItem.create!(title: "Review focus opportunity", business: businesses(:suelog))

      patch focus_review_owner_opportunity_url(opportunity)

      assert_redirected_to focus_owner_opportunities_url
      assert_equal "reviewed", opportunity.reload.status
    end

    test "focus approve marks opportunity approved and returns to owner focus" do
      opportunity = OpportunityDiscoveryItem.create!(title: "Approve focus opportunity", business: businesses(:suelog), status: "pending")

      assert_difference("OwnerDecisionLog.count", 1) do
        patch focus_approve_owner_opportunity_url(opportunity)
      end

      assert_redirected_to owner_focus_url
      assert_equal "approved", opportunity.reload.status
      assert_equal "approve", OwnerDecisionLog.last.decision_type
      assert_equal "owner_focus", OwnerDecisionLog.last.decision_source
    end

    test "focus reject marks opportunity rejected and returns to focus" do
      opportunity = OpportunityDiscoveryItem.create!(title: "Reject focus opportunity", business: businesses(:suelog))

      assert_difference("OwnerDecisionLog.count", 1) do
        patch focus_reject_owner_opportunity_url(opportunity)
      end

      assert_redirected_to owner_focus_url
      assert_equal "rejected", opportunity.reload.status
      assert_equal "reject", OwnerDecisionLog.last.decision_type
    end

    test "focus convert creates candidate and returns to focus" do
      opportunity = OpportunityDiscoveryItem.create!(title: "Convert focus opportunity", business: businesses(:suelog))

      assert_difference("ActionCandidate.count", 1) do
        assert_difference("OwnerDecisionLog.count", 1) do
          post focus_convert_to_candidate_owner_opportunity_url(opportunity)
        end
      end

      assert_redirected_to action_candidate_url(ActionCandidate.last)
      assert_equal "converted", opportunity.reload.status
      assert_equal "convert", OwnerDecisionLog.last.decision_type
    end
  end
end

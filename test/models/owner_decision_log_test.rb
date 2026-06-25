require "test_helper"

class OwnerDecisionLogTest < ActiveSupport::TestCase
  test "records action candidate snapshot" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(
      action_type: "seo_improvement",
      expected_total_value_yen: 12_000,
      confidence_score: 76,
      status: "idea"
    )

    log = OwnerDecisionLog.record!(
      subject: candidate,
      decision_type: "approve",
      decision_source: "action_candidate_detail",
      previous_status: "idea",
      new_status: "approved"
    )

    assert_equal "ActionCandidate", log.subject_type
    assert_equal candidate.id, log.subject_id
    assert_equal candidate.business, log.business
    assert_equal "seo_improvement", log.action_type
    assert_equal candidate.reload.expected_total_value_yen, log.expected_value_yen
    assert_equal 76, log.confidence
    assert_equal "idea", log.previous_status
    assert_equal "approved", log.new_status
  end

  test "records opportunity snapshot" do
    opportunity = OpportunityDiscoveryItem.create!(
      title: "Owner insight",
      business: businesses(:suelog),
      opportunity_type: "lp_test",
      expected_value_yen: 18_000,
      confidence: 82
    )

    log = OwnerDecisionLog.record!(
      subject: opportunity,
      decision_type: "convert",
      decision_source: "owner_focus",
      previous_status: "new",
      new_status: "converted"
    )

    assert_equal "OpportunityDiscoveryItem", log.subject_type
    assert_equal "lp_test", log.opportunity_type
    assert_equal 18_000, log.expected_value_yen
    assert_equal 82, log.confidence
  end

  test "does not create immediate duplicate logs" do
    candidate = action_candidates(:nagazakicho_article)

    assert_difference("OwnerDecisionLog.count", 1) do
      2.times do
        OwnerDecisionLog.record!(
          subject: candidate,
          decision_type: "approve",
          decision_source: "action_candidate_detail",
          previous_status: "idea",
          new_status: "approved"
        )
      end
    end
  end
end

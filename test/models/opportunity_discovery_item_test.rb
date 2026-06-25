require "test_helper"

class OpportunityDiscoveryItemTest < ActiveSupport::TestCase
  test "sets defaults" do
    item = OpportunityDiscoveryItem.create!(title: "Owner insight")

    assert_equal "owner_discovery", item.source_type
    assert_equal "new", item.status
    assert_equal 50, item.opportunity_score
    assert item.discovered_at.present?
    assert item.strategic_score.present?
    assert item.decision_log_coefficient.present?
  end

  test "converts to action candidate" do
    item = OpportunityDiscoveryItem.create!(
      business: businesses(:suelog),
      title: "表示回数が多い記事を伸ばす",
      description: "CTR改善より儲かるかもしれない",
      opportunity_score: 80
    )

    assert_difference("ActionCandidate.count", 1) do
      candidate = item.convert_to_action_candidate!
      assert_equal "opportunity_validation", candidate.action_type
      assert_equal "opportunity_discovery", candidate.generation_source
      assert_equal "converted", item.reload.status
      assert_equal item.id, candidate.metadata["opportunity_id"]
    end
  end

  test "stores strategic learning scores" do
    item = OpportunityDiscoveryItem.create!(
      title: "外部シグナルからLP検証",
      source_type: "google_trends",
      opportunity_type: "lp_test",
      opportunity_score: 90,
      expected_value_yen: 80_000,
      confidence: 85
    )

    assert item.long_term_profit_score.present?
    assert item.learning_value_score.present?
    assert item.exploration_value_score.present?
    assert item.strategic_adjusted_score.present?
    assert item.metadata.dig("strategic_learning", "strategic_score").present?
    assert item.metadata.dig("strategic_learning_guardrail", "clamped_adjusted_score").present?
    assert item.practicality_score.present?
    assert item.metadata.dig("practicality", "subscores").present?
  end

  test "stores business playbook score for opportunity" do
    BusinessPlaybook.create!(
      business: businesses(:suelog),
      sample_count: 20,
      confidence_score: 80,
      opportunity_type_summary: {
        "lp_test" => {
          "type" => "lp_test",
          "score" => "75",
          "sample_count" => 20
        }
      }
    )
    item = OpportunityDiscoveryItem.create!(
      business: businesses(:suelog),
      title: "LP検証Opportunity",
      source_type: "google_trends",
      opportunity_type: "lp_test",
      opportunity_score: 90
    )

    assert_equal 75.to_d, item.business_playbook_score
    assert item.metadata.dig("business_playbook", "coefficient").present?
  end
end

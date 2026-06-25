require "test_helper"

module Aicoo
  class OpportunityActionCandidateConverterTest < ActiveSupport::TestCase
    test "converts opportunity to action candidate and links it" do
      opportunity = OpportunityDiscoveryItem.create!(
        business: businesses(:suelog),
        title: "LPで検証したいExplore仮説",
        summary: "低コストLP検証に向いている",
        source_type: "google_trends",
        opportunity_type: "lp_test",
        expected_value_yen: 80_000,
        confidence: 70,
        market_signal_score: 90,
        urgency_score: 80,
        monetization_score: 75,
        feasibility_score: 85,
        competition_score: 30,
        status: "approved"
      )

      assert_difference("ActionCandidate.count", 1) do
        candidate = OpportunityActionCandidateConverter.new(opportunity).call

        assert_equal "build_lp", candidate.action_type
        assert_equal "opportunity_discovery", candidate.generation_source
        assert_equal "lab", candidate.department
        assert_equal 80_000, candidate.immediate_value_yen
        assert_equal 70, candidate.confidence_score
        assert_equal opportunity.id, candidate.metadata.fetch("opportunity_id")
        assert_equal "converted", opportunity.reload.status
        assert_equal candidate, opportunity.action_candidate
      end
    end

    test "returns existing candidate without duplication" do
      opportunity = OpportunityDiscoveryItem.create!(
        business: businesses(:suelog),
        title: "既存候補あり",
        expected_value_yen: 10_000,
        confidence: 50
      )
      existing = opportunity.convert_to_action_candidate!

      assert_no_difference("ActionCandidate.count") do
        assert_equal existing, OpportunityActionCandidateConverter.new(opportunity.reload).call
      end
    end

    test "does not convert low practicality opportunity" do
      opportunity = OpportunityDiscoveryItem.create!(
        business: businesses(:suelog),
        title: "アクセスが増えているページを改善する",
        summary: "どのページかは未定で、最適化する",
        source_type: "google_trends",
        opportunity_type: "content_test",
        expected_value_yen: 80_000,
        confidence: 70,
        status: "approved"
      )
      opportunity.update_columns(practicality_score: 20, practicality_warning: true)

      assert_no_difference("ActionCandidate.count") do
        assert_nil OpportunityActionCandidateConverter.new(opportunity).call
      end

      assert_nil opportunity.reload.action_candidate
      assert_includes opportunity.practicality_reason, "ActionCandidate化せずOpportunityに残しました"
    end
  end
end

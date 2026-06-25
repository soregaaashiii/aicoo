require "test_helper"

module Aicoo
  class EvidenceBuilderTest < ActiveSupport::TestCase
    test "builds explore evidence for opportunity" do
      source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "シーシャ 大阪 需要増加",
        description: "検索需要が上昇傾向",
        observation_type: "trend",
        score: 90
      )
      opportunity = OpportunityDiscoveryItem.create!(
        title: "シーシャ大阪LPを検証",
        source_type: "google_trends",
        source_observation: observation,
        opportunity_score: 90
      )

      result = EvidenceBuilder.new(opportunity).call

      assert_operator result.evidence_score, :>, 0
      assert result.evidence_items.any? { |item| item["source"] == "explore" }
      assert result.evidence_summary.any? { |line| line.include?("検索需要") }
    end

    test "marks missing evidence explicitly" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "改善する",
        action_type: "other",
        generation_source: "manual"
      )

      result = EvidenceBuilder.new(candidate).call

      assert result.evidence_warning
      assert_operator result.evidence_score, :<, EvidenceBuilder::INSUFFICIENT_SCORE
      assert result.evidence_summary.any? { |line| line.include?("Evidence不足") } || result.missing_sources.any?
    end
  end
end

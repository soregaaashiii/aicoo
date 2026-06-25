require "test_helper"

class ExploreObservationTest < ActiveSupport::TestCase
  test "creates observation and converts to opportunity" do
    source = ExploreDataSource.create!(name: "Reddit", source_type: "reddit")
    observation = ExploreObservation.create!(
      explore_data_source: source,
      title: "Smoking area discussion is increasing",
      description: "Reddit discussion signal",
      observation_type: "discussion",
      score: 88
    )

    assert_difference("OpportunityDiscoveryItem.count", 1) do
      opportunity = observation.convert_to_opportunity!
      assert_equal "reddit", opportunity.source_type
      assert_equal "pending", opportunity.status
      assert_equal observation, opportunity.source_observation
      assert_equal 88, opportunity.market_signal_score
      assert opportunity.expected_value_yen.positive?
      assert opportunity.confidence.positive?
      assert_equal observation.id, opportunity.metadata.fetch("explore_observation_id")
    end
    assert observation.reload.opportunity_discovery_item
    assert_equal "converted", observation.status
  end

  test "defaults status and supports review decisions" do
    source = ExploreDataSource.create!(name: "Clarity", source_type: "clarity")
    observation = ExploreObservation.create!(explore_data_source: source, title: "離脱が多い")

    assert_equal "new", observation.status

    observation.mark_reviewed!
    assert_equal "reviewed", observation.reload.status

    observation.hold!
    assert_equal "on_hold", observation.reload.status

    observation.reject!
    assert_equal "rejected", observation.reload.status
  end

  test "manual conversion can create opportunity from weak observation" do
    source = ExploreDataSource.create!(name: "Manual", source_type: "reddit")
    observation = ExploreObservation.create!(explore_data_source: source, title: "弱いが確認したい仮説", score: 40)

    assert_difference("OpportunityDiscoveryItem.count", 1) do
      opportunity = observation.convert_to_opportunity!

      assert_equal "pending", opportunity.status
      assert_equal 40, opportunity.market_signal_score
    end
  end
end

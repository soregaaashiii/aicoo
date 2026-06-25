require "test_helper"

module Aicoo
  class ExploreOpportunityGeneratorTest < ActiveSupport::TestCase
    setup do
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      ExploreDataSource.delete_all
    end

    test "creates pending opportunity from strong observation" do
      source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "シーシャ 大阪 需要増加",
        description: "検索需要が上昇傾向",
        observation_type: "trend",
        score: 90
      )

      assert_difference("OpportunityDiscoveryItem.count", 1) do
        opportunity = ExploreOpportunityGenerator.new.generate_from_observation!(observation)

        assert_equal "pending", opportunity.status
        assert_equal "google_trends", opportunity.source_type
        assert_equal "lp_test", opportunity.opportunity_type
        assert_equal observation, opportunity.source_observation
        assert_equal 90, opportunity.market_signal_score
        assert opportunity.expected_value_yen.positive?
        assert opportunity.confidence.positive?
      end

      assert_equal "converted", observation.reload.status
    end

    test "skips weak observation" do
      source = ExploreDataSource.create!(name: "Reddit", source_type: "reddit")
      observation = ExploreObservation.create!(explore_data_source: source, title: "弱い話題", score: 40)

      assert_no_difference("OpportunityDiscoveryItem.count") do
        assert_nil ExploreOpportunityGenerator.new.generate_from_observation!(observation)
      end

      assert_equal "new", observation.reload.status
    end

    test "does not create duplicate opportunity for same observation" do
      source = ExploreDataSource.create!(name: "YouTube", source_type: "youtube")
      observation = ExploreObservation.create!(explore_data_source: source, title: "動画需要増加", score: 85)

      first = ExploreOpportunityGenerator.new.generate_from_observation!(observation)

      assert_no_difference("OpportunityDiscoveryItem.count") do
        assert_equal first, ExploreOpportunityGenerator.new.generate_from_observation!(observation.reload)
      end
    end

    test "bulk generation returns created and skipped observations" do
      source = ExploreDataSource.create!(name: "X", source_type: "x")
      strong = ExploreObservation.create!(explore_data_source: source, title: "高score signal", score: 88)
      ExploreObservation.create!(explore_data_source: source, title: "低score signal", score: 50)

      result = ExploreOpportunityGenerator.generate_all_pending!

      assert_equal [ strong ], result.created.map(&:source_observation)
      assert_empty result.skipped
    end
  end
end

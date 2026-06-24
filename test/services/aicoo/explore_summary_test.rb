require "test_helper"

module Aicoo
  class ExploreSummaryTest < ActiveSupport::TestCase
    test "summarizes sources observations and conversions" do
      source = ExploreDataSource.create!(name: "YouTube", source_type: "youtube")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "YouTube search demand",
        observation_type: "trend",
        score: 92
      )
      observation.convert_to_opportunity!
      ExploreImportLog.create!(source_type: "youtube", import_format: "csv", imported_count: 3)
      ExploreObservation.create!(explore_data_source: source, title: "On hold", status: "on_hold", score: 90)

      summary = ExploreSummary.new.call

      assert_equal 1, summary.source_counts.fetch("youtube")
      assert_equal 1, summary.observation_counts.fetch("trend")
      assert_equal 1, summary.converted_opportunity_count
      assert_equal 3, summary.imported_today_count
      assert_equal 3, summary.imported_this_week_count
      assert_equal 3, summary.import_counts_by_source.fetch("youtube")
      assert_equal 0, summary.new_status_observation_count
      assert_equal 0, summary.high_score_observation_count
      assert_equal 1, summary.on_hold_observation_count
      assert_includes summary.newest_observations, observation
    end
  end
end

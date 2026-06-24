require "test_helper"

module Aicoo
  class ExploreObservationFocusQueueTest < ActiveSupport::TestCase
    test "returns top observation ordered by score and observed date" do
      source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends")
      low = ExploreObservation.create!(explore_data_source: source, title: "Low", score: 60, observed_at: 1.day.ago)
      high_old = ExploreObservation.create!(explore_data_source: source, title: "High old", score: 90, observed_at: 2.days.ago)
      high_new = ExploreObservation.create!(explore_data_source: source, title: "High new", score: 90, observed_at: Time.current)
      ExploreObservation.create!(explore_data_source: source, title: "Rejected", score: 100, status: "rejected")

      result = ExploreObservationFocusQueue.new.call

      assert_equal high_new, result.top_observation
      assert_equal [ high_new, high_old, low ], result.observations.to_a
      assert_equal 3, result.total_count
      assert_equal 2, result.high_priority_count
    end
  end
end

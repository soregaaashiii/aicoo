require "test_helper"

module Aicoo
  class ExploreDailyRoutineTest < ActiveSupport::TestCase
    setup do
      ExploreImportLog.delete_all
      ExploreObservation.delete_all
      ExploreDataSource.delete_all
      OpportunityDiscoveryItem.delete_all
    end

    test "requires import when no import happened today" do
      routine = ExploreDailyRoutine.new.call

      assert routine.import_needed
      assert_equal "import_needed", routine.routine_status
      assert_equal Rails.application.routes.url_helpers.admin_explore_import_path, routine.recommended_next_step.path
    end

    test "prioritizes high score observations after import" do
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
      source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends")
      observation = ExploreObservation.create!(explore_data_source: source, title: "High trend", score: 90)

      routine = ExploreDailyRoutine.new.call

      assert_not routine.import_needed
      assert_equal "review_observations", routine.routine_status
      assert_equal observation, routine.top_observation
      assert_equal 1, routine.high_score_observation_count
      assert_equal Rails.application.routes.url_helpers.admin_explore_observations_focus_path, routine.recommended_next_step.path
    end

    test "prioritizes opportunities when observations are clear" do
      ExploreImportLog.create!(source_type: "reddit", import_format: "text", imported_count: 1)
      opportunity = OpportunityDiscoveryItem.create!(title: "High opportunity", opportunity_score: 95)

      routine = ExploreDailyRoutine.new.call

      assert_equal "review_opportunities", routine.routine_status
      assert_equal opportunity, routine.top_opportunity
      assert_equal 1, routine.high_priority_opportunity_count
      assert_equal Rails.application.routes.url_helpers.focus_owner_opportunities_path, routine.recommended_next_step.path
    end

    test "detects overloaded routine" do
      ExploreImportLog.create!(source_type: "youtube", import_format: "text", imported_count: 21)
      source = ExploreDataSource.create!(name: "YouTube", source_type: "youtube")
      20.times do |index|
        ExploreObservation.create!(explore_data_source: source, title: "Observation #{index}", score: 50)
      end

      routine = ExploreDailyRoutine.new.call

      assert_equal "overloaded", routine.routine_status
      assert_equal 20, routine.new_observation_count
    end
  end
end

require "test_helper"

module Admin
  class ExploreControllerTest < ActionDispatch::IntegrationTest
    test "shows explore dashboard" do
      source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends", status: "active")
      ExploreObservation.create!(
        explore_data_source: source,
        title: "Trend signal",
        observation_type: "trend",
        score: 90
      )

      get admin_explore_url

      assert_response :success
      assert_includes response.body, "Explore Data Hub"
      assert_includes response.body, "Daily Routine Summary"
      assert_includes response.body, "Data Sources"
      assert_includes response.body, "Observations"
      assert_includes response.body, "Trend signal"
      assert_includes response.body, "Convert to Opportunity"
      assert_includes response.body, "Manual Import"
      assert_includes response.body, "Import History"
      assert_includes response.body, "Observation Focus"
      assert_includes response.body, "New Observations"
      assert_includes response.body, "High Score Observations"
      assert_includes response.body, "On Hold Observations"
      assert_includes response.body, "Pending Opportunities"
      assert_includes response.body, "status"
    end

    test "converts observation to opportunity" do
      source = ExploreDataSource.create!(name: "Reddit", source_type: "reddit")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "Reddit signal",
        observation_type: "discussion",
        score: 85
      )

      assert_difference("OpportunityDiscoveryItem.count", 1) do
        post admin_explore_observation_convert_to_opportunity_url(observation)
      end

      assert_redirected_to admin_explore_observations_focus_url
      assert_equal OpportunityDiscoveryItem.last, observation.reload.opportunity_discovery_item
      assert_equal "converted", observation.status
      assert_equal "pending", OpportunityDiscoveryItem.last.status
    end

    test "shows focus page and processes observation decisions" do
      source = ExploreDataSource.create!(name: "YouTube", source_type: "youtube")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "Focus signal",
        observation_type: "trend",
        score: 92
      )

      get admin_explore_observations_focus_url

      assert_response :success
      assert_includes response.body, "Explore Observation Focus"
      assert_includes response.body, "Focus signal"
      assert_includes response.body, "Convert to Opportunity"
      assert_includes response.body, "Mark Reviewed"
      assert_includes response.body, "Reject"
      assert_includes response.body, "Hold"

      patch admin_explore_observation_hold_url(observation)
      assert_redirected_to admin_explore_observations_focus_url
      assert_equal "on_hold", observation.reload.status

      observation.update!(status: "new")
      patch admin_explore_observation_reject_url(observation)
      assert_redirected_to admin_explore_observations_focus_url
      assert_equal "rejected", observation.reload.status

      observation.update!(status: "new")
      patch admin_explore_observation_review_url(observation)
      assert_redirected_to admin_explore_observations_focus_url
      assert_equal "reviewed", observation.reload.status
    end
  end
end

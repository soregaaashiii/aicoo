require "test_helper"

module Owner
  class DiscoveryReportsControllerTest < ActionDispatch::IntegrationTest
    test "shows discovery source performance report" do
      get owner_discovery_report_url

      assert_response :success
      assert_includes response.body, "Discovery Source Performance"
      assert_includes response.body, "Summary"
      assert_includes response.body, "Conversion Funnel"
      assert_includes response.body, "Accuracy"
      assert_includes response.body, "Warnings"
    end
  end
end

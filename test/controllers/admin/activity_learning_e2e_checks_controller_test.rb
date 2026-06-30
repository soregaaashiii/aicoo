require "test_helper"

module Admin
  class ActivityLearningE2eChecksControllerTest < ActionDispatch::IntegrationTest
    test "shows activity learning e2e check" do
      get admin_activity_learning_e2e_check_url(business_id: businesses(:suelog).id)

      assert_response :success
      assert_includes response.body, "Activity Learning E2E Check"
      assert_includes response.body, "SourceAppConnection active"
      assert_includes response.body, "ActivityEvaluation作成可否"
    end

    test "repairs active connection safely" do
      connection = SourceAppConnection.create!(
        business: businesses(:suelog),
        name: "Inactive Source",
        source_app: "inactive_source",
        enabled: false,
        status: "inactive"
      )

      post admin_activity_learning_e2e_check_repair_url,
           params: { business_id: businesses(:suelog).id, repair_action: "activate_connections" }

      assert_redirected_to admin_activity_learning_e2e_check_url(business_id: businesses(:suelog).id)
      assert connection.reload.enabled?
      assert_equal "active", connection.status
    end
  end
end

require "test_helper"

module Admin
  class SourceAppConnectionsControllerTest < ActionDispatch::IntegrationTest
    test "shows source app connections and default suelog rules" do
      get admin_source_app_connections_url

      assert_response :success
      assert_includes response.body, "Source App Connections"
      assert SourceAppConnection.exists?(source_app: "suelog")
    end
  end
end

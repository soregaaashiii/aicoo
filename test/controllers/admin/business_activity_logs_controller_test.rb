require "test_helper"

module Admin
  class BusinessActivityLogsControllerTest < ActionDispatch::IntegrationTest
    test "shows activity log index and detail" do
      activity_log = BusinessActivityLog.create!(
        business: businesses(:suelog),
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop作成",
        occurred_at: Time.current,
        detected_at: Time.current,
        idempotency_key: "admin-shop-created"
      )

      get admin_business_activity_logs_url
      assert_response :success
      assert_includes response.body, "Activity Logs"
      assert_includes response.body, "shop_created"

      get admin_business_activity_log_url(activity_log)
      assert_response :success
      assert_includes response.body, "Shop作成"
    end
  end
end

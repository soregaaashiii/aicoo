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

    test "index loads only columns used by the list" do
      activity_log = BusinessActivityLog.create!(
        business: businesses(:suelog),
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "2",
        title: "Shop作成",
        occurred_at: Time.current,
        detected_at: Time.current,
        changed_fields: { "large" => "changed" },
        before_snapshot: { "large" => "before" },
        after_snapshot: { "large" => "after" },
        metadata: { "large" => "metadata" },
        idempotency_key: "admin-shop-created-projection"
      )
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
        queries << payload[:sql] unless payload[:name] == "SCHEMA"
      end

      get admin_business_activity_logs_url(activity_type: "shop_created")

      assert_response :success
      assert_includes response.body, activity_log.business.name
      list_query = queries.find { |sql| sql.include?(%(FROM "business_activity_logs")) }
      assert list_query
      refute_match(/before_snapshot|after_snapshot|changed_fields|metadata/, list_query)
      assert_match(/businesses"\."name/, list_query)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end
end

require "test_helper"

class BusinessActivityLogTest < ActiveSupport::TestCase
  test "creates activity log with idempotency per business" do
    business = businesses(:suelog)

    log = BusinessActivityLog.record!(
      business:,
      attributes: {
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop作成",
        idempotency_key: "shop-1-created"
      }
    )
    duplicate = BusinessActivityLog.record!(
      business:,
      attributes: {
        source_app: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop作成 duplicate",
        idempotency_key: "shop-1-created"
      }
    )

    assert_equal log, duplicate
    assert_equal "Shop作成", duplicate.title
    assert_equal "pending", log.evaluation_status
  end
end

require "test_helper"

module Aicoo
  class ActivityLearningE2eCheckTest < ActiveSupport::TestCase
    test "returns pass warning and fail checks for business activity learning" do
      business = businesses(:suelog)
      connection = SourceAppConnection.create!(business:, name: "Test Source", source_app: "test_source")
      rule = connection.source_app_diff_rules.create!(
        name: "Shop update",
        watched_table: "shops",
        resource_type: "Shop",
        activity_type: "shop_profile_updated",
        enabled: false
      )
      BusinessActivityLog.create!(
        business:,
        source_app: "test_source",
        activity_type: "shop_profile_updated",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop更新",
        occurred_at: Time.current,
        detected_at: Time.current,
        source_method: "db_diff",
        idempotency_key: "shop-update-e2e"
      )

      result = ActivityLearningE2eCheck.new(business).call

      assert_equal business, result.business
      assert result.checks.any? { |check| check.key == "source_app_connection" && check.pass? }
      assert result.checks.any? { |check| check.key == "source_app_diff_rule" && check.fail? }

      ActivityLearningE2eCheck.repair!(business, "activate_rules")
      assert rule.reload.enabled?
    end

    test "creates cursors through safe repair" do
      business = businesses(:suelog)
      connection = SourceAppConnection.create!(business:, name: "Cursor Source", source_app: "cursor_source")
      rule = connection.source_app_diff_rules.create!(
        name: "Article update",
        watched_table: "articles",
        resource_type: "Article",
        activity_type: "article_updated"
      )

      assert_difference -> { SourceAppDiffCursor.count }, 1 do
        ActivityLearningE2eCheck.repair!(business, "create_cursors")
      end
      assert rule.reload.source_app_diff_cursor
    end
  end
end

require "test_helper"

class SourceAppDiffRuleTest < ActiveSupport::TestCase
  test "cursor is created on demand" do
    connection = SourceAppConnection.create!(
      business: businesses(:suelog),
      name: "Test App",
      source_app: "test_app"
    )
    rule = connection.source_app_diff_rules.create!(
      name: "Shop update",
      watched_table: "shops",
      resource_type: "Shop",
      activity_type: "shop_profile_updated"
    )

    assert_difference -> { SourceAppDiffCursor.count }, 1 do
      assert rule.cursor.persisted?
    end
  end
end

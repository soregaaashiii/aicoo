require "test_helper"

class SourceAppConnectionTest < ActiveSupport::TestCase
  test "ensures suelog default connection and rules" do
    SourceAppConnection.delete_all

    connection = SourceAppConnection.ensure_suelog_defaults!

    assert_equal businesses(:suelog), connection.business
    assert_equal "same_database", connection.connection_type
    assert connection.source_app_diff_rules.exists?(activity_type: "shop_created")
    assert connection.source_app_diff_rules.exists?(watched_table: "articles")
  end
end

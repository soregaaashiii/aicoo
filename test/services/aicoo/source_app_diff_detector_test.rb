require "test_helper"

module Aicoo
  class SourceAppDiffDetectorTest < ActiveSupport::TestCase
    TEST_TABLE = "source_diff_test_shops"

    setup do
      ActiveRecord::Base.connection.drop_table(TEST_TABLE, if_exists: true)
      ActiveRecord::Base.connection.create_table(TEST_TABLE) do |t|
        t.string :name
        t.string :area
        t.string :smoking_status
        t.timestamps null: false
      end
    end

    teardown do
      ActiveRecord::Base.connection.drop_table(TEST_TABLE, if_exists: true)
    end

    test "detects same database changes as activity logs" do
      business = businesses(:suelog)
      connection = SourceAppConnection.create!(business:, name: "Test Source", source_app: "test_source")
      connection.source_app_diff_rules.create!(
        name: "Shop changes",
        watched_table: TEST_TABLE,
        resource_type: "Shop",
        activity_type: "shop_created",
        watched_fields: %w[name area smoking_status],
        metadata_fields: %w[area smoking_status],
        title_template: "Shopを作成: %{name}"
      )
      now = ActiveRecord::Base.connection.quote(Time.current)
      ActiveRecord::Base.connection.execute(
        "INSERT INTO #{TEST_TABLE} (name, area, smoking_status, created_at, updated_at) " \
        "VALUES ('テスト店', '梅田', 'allowed', #{now}, #{now})"
      )

      result = SourceAppDiffDetector.new.call

      assert_equal 1, result.created_count
      activity_log = BusinessActivityLog.last
      assert_equal "db_diff", activity_log.source_method
      assert_equal "梅田", activity_log.metadata["area"]
    end
  end
end

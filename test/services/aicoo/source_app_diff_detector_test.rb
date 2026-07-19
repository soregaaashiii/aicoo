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

    test "reads suelog rules from the configured suelog database connection" do
      business = businesses(:suelog)
      connection = SourceAppConnection.find_or_create_by!(business:, source_app: "suelog") do |record|
        record.name = "吸えログ"
        record.connection_type = "same_database"
        record.enabled = true
        record.status = "active"
      end
      connection.update!(
        enabled: true,
        status: "active",
        settings: connection.settings.to_h.merge("database_connection" => "suelog")
      )
      connection.source_app_diff_rules.destroy_all
      connection.source_app_diff_rules.create!(
        name: "External shop changes",
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
        "VALUES ('外部DB店舗', '難波', 'allowed', #{now}, #{now})"
      )

      SourceAppConnection.stub(:ensure_suelog_defaults!, connection) do
        SuelogRecord.stub(:ensure_connection!, true) do
          SuelogRecord.stub(:connection, ActiveRecord::Base.connection) do
            result = SourceAppDiffDetector.new.call

            assert_equal 1, result.created_count
          end
        end
      end

      activity_log = BusinessActivityLog.find_by!(resource_type: "Shop", title: "Shopを作成: 外部DB店舗")
      assert_equal "db_diff", activity_log.source_method
      assert_equal business, activity_log.business
    end
  end
end

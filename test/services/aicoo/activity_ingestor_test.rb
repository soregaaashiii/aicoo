require "test_helper"

module Aicoo
  class ActivityIngestorTest < ActiveSupport::TestCase
    TEST_TABLE = "shops"

    setup do
      Object.send(:remove_const, :Shop) if Object.const_defined?(:Shop)
      ActiveRecord::Base.connection.drop_table(TEST_TABLE, if_exists: true)
      ActiveRecord::Base.connection.create_table(TEST_TABLE) do |t|
        t.string :name
        t.string :area
        t.string :smoking_status
        t.string :station
        t.string :source
        t.string :tabelog_url
        t.timestamps null: false
      end

      Object.const_set(:Shop, Class.new(ApplicationRecord) do
        self.table_name = "shops"
        include AicooActivityTrackable
      end)

      connection = SourceAppConnection.find_or_create_by!(business: businesses(:suelog), source_app: "suelog") do |record|
        record.name = "吸えログTest"
        record.connection_type = "same_database"
        record.enabled = true
        record.status = "active"
      end
      connection.update!(enabled: true, status: "active")
      connection.source_app_diff_rules.find_or_create_by!(name: "Shop callback") do |rule|
        rule.watched_table = "shops"
        rule.resource_type = "Shop"
        rule.activity_type = "shop_created"
        rule.watched_fields = %w[name area smoking_status station source tabelog_url]
        rule.metadata_fields = %w[area smoking_status station source tabelog_url]
        rule.title_template = "店舗を追加: %{name}"
      end
    end

    teardown do
      Object.send(:remove_const, :Shop) if Object.const_defined?(:Shop)
      ActiveRecord::Base.connection.drop_table(TEST_TABLE, if_exists: true)
    end

    test "creates activity log when shop is created" do
      assert_difference -> { BusinessActivityLog.where(resource_type: "Shop", activity_type: "shop_created").count }, 1 do
        Shop.create!(name: "テスト喫煙店", area: "梅田", smoking_status: "allowed", station: "大阪", source: "manual")
      end

      activity_log = BusinessActivityLog.where(resource_type: "Shop", activity_type: "shop_created").last
      assert_equal businesses(:suelog), activity_log.business
      assert_equal "logger", activity_log.source_method
      assert_includes activity_log.title, "店舗を追加"
      assert_equal "梅田", activity_log.metadata["area"]
    end

    test "creates activity log when shop is updated" do
      shop = Shop.create!(name: "更新前店舗", area: "難波", smoking_status: "unknown")

      assert_difference -> { BusinessActivityLog.where(resource_type: "Shop", activity_type: "smoking_status_updated").count }, 1 do
        shop.update!(smoking_status: "allowed")
      end
    end

    test "creates activity log when shop is destroyed" do
      shop = Shop.create!(name: "削除店舗", area: "天満", smoking_status: "unknown")

      assert_difference -> { BusinessActivityLog.where(resource_type: "Shop", activity_type: "shop_deleted").count }, 1 do
        shop.destroy!
      end
    end

    test "queues warning payload when business cannot be linked" do
      SourceAppDiffRule.delete_all
      SourceAppConnection.delete_all

      assert_no_difference -> { BusinessActivityLog.count } do
        assert_difference -> { AicooActivityLogQueue.where("metadata ->> 'unlinked_activity' = ?", "true").count }, 1 do
          Shop.create!(name: "未紐付け店舗", area: "京都", smoking_status: "unknown")
        end
      end
    end
  end
end

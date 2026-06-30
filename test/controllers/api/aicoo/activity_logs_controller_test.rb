require "test_helper"

module Api
  module Aicoo
    class ActivityLogsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @previous_key = ENV["AICOO_ACTIVITY_API_KEY"]
        @previous_token = ENV["AICOO_ACTIVITY_API_TOKEN"]
        ENV["AICOO_ACTIVITY_API_KEY"] = "test-key"
        ENV.delete("AICOO_ACTIVITY_API_TOKEN")
      end

      teardown do
        ENV["AICOO_ACTIVITY_API_KEY"] = @previous_key
        ENV["AICOO_ACTIVITY_API_TOKEN"] = @previous_token
      end

      test "creates activity log by api key and business key" do
        business = businesses(:suelog)
        business.update!(project_key: "suelog")

        assert_difference -> { BusinessActivityLog.count }, 1 do
          post api_aicoo_activity_logs_url,
               params: {
                 business_key: "suelog",
                 source_app: "suelog",
                 activity_type: "article_published",
                 resource_type: "Article",
                 resource_id: "10",
                 title: "記事公開",
                 idempotency_key: "article-10-published"
               },
               headers: { "Authorization" => "Bearer test-key" },
               as: :json
        end

        assert_response :created
        assert_equal "article_published", BusinessActivityLog.last.activity_type
      end

      test "does not duplicate same idempotency key" do
        business = businesses(:suelog)

        2.times do
          post api_aicoo_activity_logs_url,
               params: {
                 business_id: business.id,
                 source_app: "suelog",
                 activity_type: "shop_created",
                 resource_type: "Shop",
                 resource_id: "2",
                 title: "Shop作成",
                 idempotency_key: "shop-2-created"
               },
               headers: { "X-AICOO-API-Key" => "test-key" },
               as: :json
        end

        assert_response :success
        assert_equal 1, BusinessActivityLog.where(idempotency_key: "shop-2-created").count
      end

      test "rejects invalid api key" do
        post api_aicoo_activity_logs_url, params: {}, headers: { "Authorization" => "Bearer bad" }, as: :json

        assert_response :unauthorized
      end

      test "rejects missing token" do
        post api_aicoo_activity_logs_url, params: {}, as: :json

        assert_response :unauthorized
      end

      test "creates shop activity from suelog payload and activity token" do
        ENV.delete("AICOO_ACTIVITY_API_KEY")
        ENV["AICOO_ACTIVITY_API_TOKEN"] = "activity-token"
        SourceAppConnection.ensure_suelog_defaults!

        assert_difference -> { BusinessActivityLog.where(resource_type: "Shop", source_app: "suelog").count }, 1 do
          post api_aicoo_activity_logs_url,
               params: {
                 business_key: "suelog",
                 activity_type: "data_added",
                 source_type: "shop",
                 source_id: "123",
                 title: "店舗を追加",
                 summary: "梅田の喫煙可能店舗を追加",
                 occurred_at: Time.current.iso8601,
                 metadata: {
                   area: "梅田",
                   smoking_status: "allowed"
                 }
               },
               headers: { "Authorization" => "Bearer activity-token" },
               as: :json
        end

        assert_response :created
        activity_log = BusinessActivityLog.last
        assert_equal businesses(:suelog), activity_log.business
        assert_equal "data_added", activity_log.activity_type
        assert_equal "123", activity_log.resource_id
        assert_equal "梅田の喫煙可能店舗を追加", activity_log.diff_summary
        assert_equal "梅田", activity_log.metadata["area"]
      end
    end
  end
end

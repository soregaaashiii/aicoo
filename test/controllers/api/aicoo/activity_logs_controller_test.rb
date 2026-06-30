require "test_helper"

module Api
  module Aicoo
    class ActivityLogsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @previous_key = ENV["AICOO_ACTIVITY_API_KEY"]
        ENV["AICOO_ACTIVITY_API_KEY"] = "test-key"
      end

      teardown do
        ENV["AICOO_ACTIVITY_API_KEY"] = @previous_key
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
    end
  end
end

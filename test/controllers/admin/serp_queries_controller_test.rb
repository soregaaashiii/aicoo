require "test_helper"

module Admin
  class SerpQueriesControllerTest < ActionDispatch::IntegrationTest
    test "index shows serp queries" do
      query = SerpQuery.create!(
        business: businesses(:suelog),
        query: "大阪 喫煙 カフェ",
        category: "existing_business",
        priority: 20
      )

      get admin_serp_queries_url(business_id: query.business_id)

      assert_response :success
      assert_includes response.body, "SERP検索クエリ"
      assert_includes response.body, query.query
    end

    test "creates serp query" do
      assert_difference("SerpQuery.count", 1) do
        post admin_serp_queries_url, params: {
          serp_query: {
            business_id: businesses(:suelog).id,
            query: "難波 喫煙",
            category: "existing_business",
            priority: 30,
            daily_limit: 1,
            country: "jp",
            language: "ja",
            enabled: "1"
          }
        }
      end

      assert_redirected_to %r{/admin/serp_queries\?business_id=#{businesses(:suelog).id}#serp-query-\d+}
      assert_equal "難波 喫煙", SerpQuery.last.query
    end

    test "toggles serp query" do
      query = SerpQuery.create!(business: businesses(:suelog), query: "梅田 喫煙", category: "existing_business", enabled: true)

      patch toggle_admin_serp_query_url(query)

      assert_redirected_to admin_serp_queries_url(business_id: query.business_id)
      assert_not query.reload.enabled?
    end
  end
end

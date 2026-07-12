require "test_helper"

module Aicoo
  module Serp
    class ScanRunnerTest < ActiveSupport::TestCase
      test "does not generate queries from existing business names" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        business.business_serp_keywords.create!(keyword: "#{business.name} 比較", source: "manual", status: "active")
        business.serp_queries.create!(query: "#{business.name} おすすめ", category: "existing_business", enabled: true)

        assert_equal [], ScanRunner.queries_for_business(business, max_queries_per_business: 10)
      end

      test "market exploration queries use market problem words and optional region" do
        business = Business.new(name: "AICOO Market Exploration", business_type: "exploration")

        queries = ScanRunner.queries_for_business(
          business,
          max_queries_per_business: 5,
          exploration_mode: "keyword",
          exploration_query: "フリーランス 請求",
          exploration_region: "大阪"
        )

        assert_equal [
          "フリーランス 請求 大阪",
          "フリーランス 請求 困る 大阪",
          "フリーランス 請求 料金 大阪",
          "フリーランス 請求 自動化 大阪",
          "フリーランス 請求 代行 大阪"
        ], queries
      end

      test "scan without business input writes analyses to internal exploration business" do
        with_adapter_result do
          result = ScanRunner.new(
            provider: :serper,
            max_queries_per_business: 1,
            exploration_mode: "ai_auto"
          ).call

          system_business = Business.find_by!(name: "AICOO Market Exploration")
          assert_equal 1, result.target_business_count
          assert_equal 1, result.query_count
          assert_equal 1, result.success_count
          assert_equal "success", system_business.serp_analyses.order(:created_at).last.status
          assert_equal 0, businesses(:suelog).serp_analyses.count
        end
      end

      private

      def with_adapter_result
        payload = {
          provider: "serper",
          type: "google_search",
          query: "個人事業主 業務 自動化",
          location: "Japan",
          language: "ja",
          fetched_at: Time.current.iso8601,
          organic_results: [
            {
              position: 1,
              title: "個人事業主向け業務自動化",
              url: "https://example.com",
              displayed_url: "example.com",
              snippet: "請求や管理を自動化",
              source: "example",
              raw: {}
            }
          ],
          people_also_ask: [],
          related_searches: [],
          ai_overview: nil,
          raw_response: {}
        }
        singleton = class << Adapter; self; end
        original_call = Adapter.method(:call)
        singleton.define_method(:call) { |**_kwargs| SearchResult.new(payload) }
        yield
      ensure
        singleton.define_method(:call) { |*args, **kwargs| original_call.call(*args, **kwargs) }
      end
    end
  end
end

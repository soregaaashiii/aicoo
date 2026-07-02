require "test_helper"

module Aicoo
  module Serp
    class ScanRunnerTest < ActiveSupport::TestCase
      test "scans launched real businesses and skips system businesses" do
        real_business = businesses(:suelog)
        real_business.update!(status: "launched")
        system_business = Business.create!(
          name: "AICOO Analytics Import",
          description: "system import holder",
          status: "launched"
        )

        with_adapter_result do
          result = ScanRunner.new(provider: :serper, max_queries_per_business: 1).call

          assert_operator result.query_count, :>=, 1
          assert_equal 0, system_business.serp_analyses.count
          assert_operator real_business.serp_analyses.count, :>=, 1
          assert_equal "success", real_business.serp_analyses.order(:created_at).last.status
        end
      end

      test "records failed analysis when provider fails" do
        business = businesses(:suelog)
        business.update!(status: "launched")

        with_adapter_error(RuntimeError.new("provider failed")) do
          result = ScanRunner.new(provider: :serper, max_queries_per_business: 1).call

          assert_operator result.failed_count, :>=, 1
          latest = business.serp_analyses.order(:created_at).last
          assert_equal "failed", latest.status
          assert_includes latest.error_message, "provider failed"
        end
      end

      test "uses active business serp keywords before legacy data source keywords" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        business.business_serp_keywords.create!(
          keyword: "大阪 喫煙 居酒屋",
          source: "manual",
          status: "active",
          priority_score: 80
        )
        setting = business.business_data_source_settings.find_or_initialize_by(source_key: "serp")
        setting.update!(metadata: { "connection_fields" => { "keyword" => "古い キーワード" } })

        assert_equal [ "大阪 喫煙 居酒屋" ], ScanRunner.queries_for_business(business, max_queries_per_business: 1)

        with_adapter_result do
          ScanRunner.new(provider: :serper, max_queries_per_business: 1, target_businesses: [ business ]).call
        end

        keyword = business.business_serp_keywords.find_by!(keyword: "大阪 喫煙 居酒屋")
        assert_equal 1, keyword.check_count
        assert_equal 1, keyword.latest_rank
        assert keyword.last_checked_at.present?
        assert_equal "success", keyword.metadata_json["latest_serp_status"]
      end

      test "uses serp queries before keyword records and updates query counters" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        business.business_serp_keywords.create!(
          keyword: "古い キーワード",
          source: "manual",
          status: "active",
          priority_score: 100
        )
        serp_query = business.serp_queries.create!(
          query: "警備 AI",
          category: "existing_business",
          enabled: true,
          priority: 10,
          daily_limit: 1
        )

        assert_equal [ "警備 AI" ], ScanRunner.queries_for_business(business, max_queries_per_business: 1)

        with_adapter_result do
          ScanRunner.new(provider: :serper, max_queries_per_business: 1, target_businesses: [ business ]).call
        end

        serp_query.reload
        assert_equal 1, serp_query.success_count
        assert_equal 0, serp_query.failure_count
        assert serp_query.last_run_at.present?
        assert serp_query.last_success_at.present?
        latest = business.serp_analyses.order(:created_at).last
        assert_equal serp_query.id, latest.raw_summary["serp_query_id"]
      end

      test "updates serp query failure count when provider fails" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        serp_query = business.serp_queries.create!(
          query: "失敗 テスト",
          category: "existing_business",
          enabled: true,
          priority: 10,
          daily_limit: 1
        )

        with_adapter_error(RuntimeError.new("provider failed")) do
          ScanRunner.new(provider: :serper, max_queries_per_business: 1, target_businesses: [ business ]).call
        end

        serp_query.reload
        assert_equal 0, serp_query.success_count
        assert_equal 1, serp_query.failure_count
      end

      private

      def with_adapter_result
        payload = {
          provider: "serper",
          type: "google_search",
          query: "吸えログ",
          location: "Japan",
          language: "ja",
          fetched_at: Time.current.iso8601,
          organic_results: [
            {
              position: 1,
              title: "吸えログ",
              url: "https://example.com",
              displayed_url: "example.com",
              snippet: "喫煙できる店舗情報",
              source: "example",
              raw: {}
            }
          ],
          people_also_ask: [],
          related_searches: [],
          ai_overview: nil,
          raw_response: {}
        }
        with_adapter_call(-> { SearchResult.new(payload) }) { yield }
      end

      def with_adapter_error(error)
        with_adapter_call(-> { raise error }) { yield }
      end

      def with_adapter_call(replacement)
        singleton = class << Adapter; self; end
        original_call = Adapter.method(:call)
        singleton.define_method(:call) { |**_kwargs| replacement.call }
        yield
      ensure
        singleton.define_method(:call) { |*args, **kwargs| original_call.call(*args, **kwargs) }
      end
    end
  end
end

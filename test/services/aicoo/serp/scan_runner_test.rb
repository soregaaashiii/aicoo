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

require "test_helper"

module Aicoo
  module Serp
    class RunExecutorTest < ActiveSupport::TestCase
      test "creates serp run and links analyses" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        serp_query = business.serp_queries.create!(
          query: "大阪 喫煙 テスト #{SecureRandom.hex(4)}",
          category: "existing_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 1
        )

        with_adapter_result do
          run = Aicoo::Serp::RunExecutor.new(executed_by: "manual", force: true, serp_query:).call

          assert_equal "success", run.status
          assert_equal "manual", run.executed_by
          assert_equal 1, run.query_count
          assert_equal 1, run.success_count
          assert_equal run, business.serp_analyses.order(:created_at).last.serp_run
        end
      end

      private

      def with_adapter_result
        payload = {
          provider: "serper",
          type: "google_search",
          query: "大阪 喫煙",
          location: "Japan",
          language: "ja",
          fetched_at: Time.current.iso8601,
          organic_results: [
            {
              position: 1,
              title: "大阪の喫煙カフェ",
              url: "https://example.com",
              displayed_url: "example.com",
              snippet: "喫煙情報",
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

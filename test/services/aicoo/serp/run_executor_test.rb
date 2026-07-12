require "test_helper"

module Aicoo
  module Serp
    class RunExecutorTest < ActiveSupport::TestCase
      test "manual serp run explores markets without business input and creates exploring business" do
        seed = "フリーランス 請求 #{SecureRandom.hex(4)}"

        with_adapter_result(query: seed) do
          assert_difference("Business.real_businesses.count", 1) do
            run = Aicoo::Serp::RunExecutor.new(
              executed_by: "manual",
              force: true,
              exploration_mode: "keyword",
              exploration_query: seed,
              exploration_region: "大阪"
            ).call

            assert_equal "success", run.status
            assert_equal "new_business_exploration", run.metadata["purpose"]
            assert_equal [], run.metadata["target_business_ids"]
            assert_equal "keyword", run.metadata["exploration_mode"]
            assert_equal seed, run.metadata["exploration_query"]
            assert_equal "大阪", run.metadata["exploration_region"]
            assert_equal true, run.metadata["legacy_business_serp_disabled"]

            system_business = Business.find_by!(name: "AICOO Market Exploration")
            assert Business.system_businesses.exists?(id: system_business.id)
            assert_equal 1, system_business.serp_analyses.where(serp_run: run).count

            discovery = run.metadata.to_h["new_business_discovery"].to_h
            candidate = ActionCandidate.find(discovery.fetch("candidate_ids").first)
            assert_equal "new_business", candidate.department
            assert_equal "serp", candidate.generation_source
            assert_equal "done", candidate.status
            assert candidate.business
            assert_equal "exploring", candidate.business.status
            assert Business.real_businesses.exists?(id: candidate.business_id)
          end
        end
      end

      test "run executor does not accept business scoped serp arguments" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)

        assert_raises(ArgumentError) do
          Aicoo::Serp::RunExecutor.new(
            executed_by: "manual",
            force: true,
            business_id: business.id,
            exploration_mode: "ai_auto"
          )
        end
      end

      private

      def with_adapter_result(query: "個人事業主 業務 自動化")
        payload = {
          provider: "serper",
          type: "google_search",
          query:,
          location: "Japan",
          language: "ja",
          fetched_at: Time.current.iso8601,
          organic_results: [
            {
              position: 1,
              title: "#{query}を解決するサービス",
              url: "https://example.com",
              displayed_url: "example.com",
              snippet: "業務課題を解決します",
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

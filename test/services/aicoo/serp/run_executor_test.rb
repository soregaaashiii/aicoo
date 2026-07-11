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

      test "selected business run does not execute other business fallback queries" do
        business = businesses(:suelog)
        other_business = businesses(:cards)
        business.update!(status: "launched", serp_enabled: true)
        other_business.update!(status: "launched", serp_enabled: true)
        business_query = business.serp_queries.create!(
          query: "梅田 喫煙 選択 #{SecureRandom.hex(4)}",
          category: "existing_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )
        other_business.serp_queries.create!(
          query: "名刺 共有 対象外 #{SecureRandom.hex(4)}",
          category: "existing_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )

        with_adapter_result do
          run = Aicoo::Serp::RunExecutor.new(executed_by: "manual", target_businesses: [ business ]).call

          assert_equal "success", run.status
          assert_equal [ business_query.id ], run.run_plan_rows.map { |row| row["serp_query_id"] }
          assert_equal 1, business.serp_analyses.where(serp_run: run).count
          assert_equal 0, other_business.serp_analyses.where(serp_run: run).count
          assert run.plan_rows.all? { |row| row["business_id"] == business.id }
        end
      end

      test "serp run discovers new business candidate and auto adds exploring business" do
        business = businesses(:cards)
        business.update!(status: "launched", serp_enabled: true)
        serp_query = business.serp_queries.create!(
          query: "請求 管理 個人事業主 自動化 #{SecureRandom.hex(4)}",
          category: "new_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )

        with_adapter_result(query: serp_query.query) do
          assert_difference("Business.real_businesses.count", 1) do
            run = Aicoo::Serp::RunExecutor.new(executed_by: "manual", force: true, serp_query:).call

            discovery = run.metadata.to_h["new_business_discovery"].to_h
            assert_equal 1, discovery["new_business_candidate_count"]
            assert_equal 0, discovery["failed_count"]

            candidate = ActionCandidate.find(discovery.fetch("candidate_ids").first)
            assert_equal "serp", candidate.generation_source
            assert_equal "new_business", candidate.department
            assert_equal "new_business", candidate.action_type
            assert_equal "new_business", candidate.metadata["candidate_kind"]
            assert_equal serp_query.query, candidate.metadata["source_query"]
            assert_equal "done", candidate.status
            assert candidate.business
            assert_equal "exploring", candidate.business.status
            assert Business.real_businesses.where(id: candidate.business_id).exists?
          end
        end
      end

      test "existing business serp improvement does not create duplicate business" do
        business = businesses(:suelog)
        business.update!(status: "launched", serp_enabled: true)
        serp_query = business.serp_queries.create!(
          query: "大阪 喫煙 居酒屋 #{SecureRandom.hex(4)}",
          category: "existing_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )

        with_adapter_result(query: serp_query.query) do
          assert_no_difference("Business.real_businesses.count") do
            run = Aicoo::Serp::RunExecutor.new(executed_by: "manual", force: true, serp_query:).call
            assert_equal 0, run.metadata.to_h.dig("new_business_discovery", "new_business_candidate_count").to_i
          end
        end
      end

      private

      def with_adapter_result(query: "大阪 喫煙")
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

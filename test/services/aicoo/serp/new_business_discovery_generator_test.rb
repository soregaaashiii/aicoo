require "test_helper"

module Aicoo
  module Serp
    class NewBusinessDiscoveryGeneratorTest < ActiveSupport::TestCase
      test "turns search query into a service business name instead of reusing query" do
        business = businesses(:cards)
        serp_run = SerpRun.create!(
          status: "success",
          executed_by: "manual",
          started_at: 1.hour.ago,
          finished_at: 55.minutes.ago,
          query_count: 1,
          success_count: 1,
          failure_count: 0
        )
        serp_query = business.serp_queries.create!(
          query: "飲食店 代行 大阪",
          category: "new_business",
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )
        analysis = business.serp_analyses.create!(
          serp_run:,
          keyword: "飲食店 代行 大阪",
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 3,
          competition_score: 30,
          analyzed_at: Time.current,
          raw_summary: { "serp_query_id" => serp_query.id }
        )
        analysis.serp_results.create!(
          position: 1,
          title: "飲食店向けGoogleマップ運用代行",
          url: "https://example.com/meo",
          snippet: "大阪の飲食店の口コミ、MEO、Googleマップ集客を代行します。"
        )
        analysis.serp_results.create!(
          position: 2,
          title: "飲食店SNS集客代行",
          url: "https://example.com/sns",
          snippet: "InstagramとLINEで飲食店の予約を増やす運用代行。"
        )

        result = Aicoo::Serp::NewBusinessDiscoveryGenerator.new(serp_run:).call

        assert_equal 1, result.created_count
        candidate = result.candidates.first
        assert_equal "done", candidate.status
        assert_equal "exploring", candidate.business.status
        assert_equal "飲食店 代行 大阪", candidate.metadata["source_query"]
        assert_not_equal "飲食店 代行 大阪の検証事業", candidate.title
        assert_no_match(/飲食店 代行 大阪の検証事業/, candidate.business.name)
        assert_match(/飲食店.*(代行|支援|運用|集客|ツール|ナビ)/, candidate.business.name)
        assert_equal false, candidate.metadata.dig("business_name_quality", "query_reused_as_name")
        assert_equal true, candidate.metadata.dig("business_name_quality", "understandable_service_name")
        assert_includes candidate.metadata["business_name_reason"], "検索語をそのまま使わず"
        assert candidate.metadata["market_analysis"].present?
        assert candidate.metadata["existing_competitors"].present?
        assert candidate.metadata["differentiation"].present?
      end
    end
  end
end

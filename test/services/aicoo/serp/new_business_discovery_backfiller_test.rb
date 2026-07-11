require "test_helper"

module Aicoo
  module Serp
    class NewBusinessDiscoveryBackfillerTest < ActiveSupport::TestCase
      test "backfills exploring business from stored serp results without new scan" do
        business = businesses(:cards)
        serp_run = create_serp_run
        analysis = create_analysis(
          business:,
          serp_run:,
          keyword: "請求 管理 個人事業主 自動化 #{SecureRandom.hex(4)}",
          serp_query_category: "existing_business"
        )
        create_result(analysis, title: "請求管理を自動化するサービス", url: "https://example.com/invoice-automation", snippet: "個人事業主の請求管理が面倒な方向け")

        assert_difference("Business.real_businesses.count", 1) do
          result = Aicoo::Serp::NewBusinessDiscoveryBackfiller.call(scope: SerpRun.where(id: serp_run.id))

          assert_equal 1, result.serp_runs_checked
          assert_equal 1, result.serp_analyses_checked
          assert_equal 1, result.serp_results_checked
          assert_equal 1, result.new_business_candidates_created
          assert_equal 1, result.businesses_created
          assert_equal 0, result.failed

          candidate = ActionCandidate.find(result.candidate_ids.first)
          assert_equal "serp", candidate.generation_source
          assert_equal "new_business", candidate.department
          assert_equal "new_business", candidate.action_type
          assert_equal "done", candidate.status
          assert_equal "exploring", candidate.business.status
          assert_equal serp_run.id, candidate.metadata["serp_run_id"]
          assert candidate.metadata["discovery_fingerprint"].present?
        end

        assert_no_difference("Business.real_businesses.count") do
          result = Aicoo::Serp::NewBusinessDiscoveryBackfiller.call(scope: SerpRun.where(id: serp_run.id))

          assert_equal 0, result.new_business_candidates_created
          assert_equal 1, result.duplicates_skipped
        end
      end

      test "does not convert branded existing business serp result into new business" do
        business = businesses(:suelog)
        serp_run = create_serp_run
        analysis = create_analysis(
          business:,
          serp_run:,
          keyword: "吸えログ 比較",
          serp_query_category: "existing_business"
        )
        create_result(analysis, title: "ログ管理システム比較", url: "https://it-trend.jp/log_management/article/84-0008", snippet: "ログ管理ツール比較")
        business.action_candidates.create!(
          title: "既存SERP改善候補",
          description: "既存候補",
          action_type: "seo_improvement",
          department: "revenue",
          generation_source: "serp",
          status: "idea",
          immediate_value_yen: 10_000,
          success_probability: 0.2,
          expected_hours: 1,
          metadata: { "source_query" => analysis.keyword }
        )

        assert_no_difference("Business.real_businesses.count") do
          result = Aicoo::Serp::NewBusinessDiscoveryBackfiller.call(scope: SerpRun.where(id: serp_run.id))

          assert_equal 0, result.new_business_candidates_created
          assert_operator result.insufficient_data_skipped, :>=, 1
        end
      end

      private

      def create_serp_run
        SerpRun.create!(
          status: "success",
          executed_by: "manual",
          started_at: 1.day.ago,
          finished_at: 1.day.ago + 1.minute,
          query_count: 1,
          success_count: 1,
          failure_count: 0
        )
      end

      def create_analysis(business:, serp_run:, keyword:, serp_query_category:)
        serp_query = business.serp_queries.create!(
          query: keyword,
          category: serp_query_category,
          status: "active",
          enabled: true,
          priority: 1,
          daily_limit: 5
        )
        business.serp_analyses.create!(
          serp_run:,
          keyword:,
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 1,
          competition_score: 30,
          analyzed_at: 1.day.ago,
          raw_summary: { "serp_query_id" => serp_query.id }
        )
      end

      def create_result(analysis, title:, url:, snippet:)
        analysis.serp_results.create!(
          position: 1,
          title:,
          url:,
          snippet:
        )
      end
    end
  end
end

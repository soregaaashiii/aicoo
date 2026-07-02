require "test_helper"

module Aicoo
  module Serp
    class E2eCheckTest < ActiveSupport::TestCase
      setup do
        DataSourceCostProfile.ensure_defaults!
        DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "configured")
        @business = businesses(:suelog)
        @business.update!(status: "launched", serp_enabled: true)
      end

      test "fails when active keywords are missing" do
        @business.business_serp_keywords.delete_all

        result = E2eCheck.new(@business).call
        keyword_check = result.checks.find { |check| check.key == :keywords }

        assert_equal "fail", keyword_check.status
        assert_equal "regenerate_keyword_suggestions", keyword_check.repair_action
        assert_equal "broken", result.overall_status
      end

      test "passes keyword and scan result checks when serp data exists" do
        keyword = @business.business_serp_keywords.create!(keyword: "梅田 喫煙", source: "manual", status: "active")
        serp_run = SerpRun.create!(
          status: "success",
          started_at: Time.current,
          finished_at: Time.current,
          executed_by: "manual",
          query_count: 1,
          success_count: 1
        )
        analysis = @business.serp_analyses.create!(
          serp_run:,
          keyword: keyword.keyword,
          analyzed_at: Time.current,
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 1,
          competition_score: 40,
          raw_summary: { "related_searches" => [ "梅田 喫煙 カフェ" ], "people_also_ask_count" => 1 }
        )
        analysis.serp_results.create!(position: 1, title: "喫煙カフェ", url: "https://example.com", snippet: "梅田")
        keyword.update!(last_checked_at: Time.current, check_count: 1, latest_rank: 1)
        @business.action_candidates.create!(
          title: "SERP候補",
          action_type: "seo_improvement",
          generation_source: "serp",
          status: "idea",
          evaluation_reason: "SERP"
        )

        result = E2eCheck.new(@business).call

        assert_equal "pass", result.checks.find { |check| check.key == :keywords }.status
        assert_equal "pass", result.checks.find { |check| check.key == :serp_result }.status
        assert_equal "pass", result.checks.find { |check| check.key == :action_candidate }.status
        assert_equal 1, result.pipeline_metrics[:fetched_query_count]
        assert_equal 1, result.pipeline_metrics[:saved_analysis_count]
        assert_equal 1, result.pipeline_metrics[:saved_result_count]
        assert_equal 1, result.pipeline_metrics[:business_analysis_count]
      end

      test "reports business linkage failure when latest serp run succeeded for another business" do
        @business.serp_queries.create!(query: "梅田 喫煙", category: "existing_business", status: "active", enabled: true)
        other_business = businesses(:cards)
        other_business.update!(status: "launched", serp_enabled: true)
        serp_run = SerpRun.create!(
          status: "success",
          started_at: Time.current,
          finished_at: Time.current,
          executed_by: "scheduler",
          query_count: 12,
          success_count: 12,
          failure_count: 0
        )
        analysis = other_business.serp_analyses.create!(
          serp_run:,
          keyword: "別Business クエリ",
          analyzed_at: Time.current,
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 1
        )
        analysis.serp_results.create!(position: 1, title: "別Business", url: "https://example.com", snippet: "ok")

        result = E2eCheck.new(@business).call
        serp_result_check = result.checks.find { |check| check.key == :serp_result }

        assert_equal "fail", serp_result_check.status
        assert_includes serp_result_check.message, "選択BusinessのSerpAnalysis保存0件"
        assert_equal "business_serp_analysis_missing", serp_result_check.details[:fail_reason]
        assert_equal 12, result.pipeline_metrics[:fetched_query_count]
        assert_equal 1, result.pipeline_metrics[:saved_result_count]
        assert_equal 0, result.pipeline_metrics[:business_analysis_count]
        assert_equal "broken", result.overall_status
      end

      test "repair approves pending keywords" do
        pending = @business.business_serp_keywords.create!(keyword: "難波 喫煙", source: "ai_suggested", status: "pending")

        E2eCheck.repair!(business: @business, action: "approve_pending_keywords")

        assert_equal "active", pending.reload.status
      end
    end
  end
end

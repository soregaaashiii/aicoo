require "test_helper"

module Aicoo
  class ArticleOpportunityAnalyzerSnapshotTest < ActiveSupport::TestCase
    setup do
      @business = Business.create!(name: "吸えログ Snapshot Analyzer", metadata: { "business_key" => "suelog" })
      AicooDataSnapshot.where(source_type: "article_analytics").delete_all
    end

    test "analyzes article analytics snapshots without calculating expected profit" do
      snapshot = create_article_snapshot(
        article_id: 101,
        path: "/articles/higashidori-smoking-izakaya",
        title: "東通り 居酒屋 喫煙可",
        gsc: { "available" => true, "impressions" => 6_000, "clicks" => 60, "ctr" => 0.01, "average_position" => 12, "query_count" => 4 },
        ga4: { "available" => true, "pageviews" => 700, "active_users" => 240, "sessions" => 300, "engagement_seconds" => 42_000 },
        shop_click: { "available" => true, "total_clicks" => 3, "article_shop_clicks" => 3 },
        article: { "title" => "東通り 居酒屋 喫煙可", "word_count" => 900, "internal_link_count" => 0, "shop_count" => 3, "verified_shop_count" => 1 },
        learning: { "improvement_count" => 2, "improvement_success_count" => 1 }
      )

      result = ArticleOpportunityAnalyzer.from_snapshots(business: @business)

      assert_equal 1, result.analyzed_count
      article_result = result.article_results.first
      assert_equal snapshot.id, article_result.snapshot_id
      assert_operator article_result.opportunity_score, :>, 0
      assert_operator article_result.search_demand_score, :>, 0
      assert_operator article_result.improvement_potential_score, :>, 0
      assert_operator article_result.expected_improvement_score, :>, 0
      assert article_result.score_breakdown.key?("seo_opportunity")
      assert article_result.score_breakdown.key?("learning_confidence")
      assert article_result.metadata.key?("search_demand_score")
      assert article_result.metadata.key?("improvement_potential_score")
      assert article_result.metadata.key?("expected_improvement_score")
      assert article_result.metadata.key?("success_probability")
      assert article_result.metadata.key?("estimated_work_hours")
      assert article_result.metadata.key?("business_value")
      assert article_result.candidate_drafts.any?
      assert_nil article_result.metadata["expected_profit_yen"]
      assert_equal false, article_result.metadata["expected_profit_calculated"]
    end

    test "dry run does not create action candidates" do
      create_article_snapshot(article_id: 102, path: "/articles/umeda-smoking-cafe")

      assert_no_difference("ActionCandidate.count") do
        result = ArticleOpportunityAnalyzer.from_snapshots(business: @business, apply: false)
        assert_equal "dry-run", result.mode
        assert_operator result.action_candidate_count, :>, 0
      end
    end

    test "apply creates archived comparison candidates only" do
      create_article_snapshot(article_id: 103, path: "/articles/namba-smoking-izakaya")

      before_count = ActionCandidate.count
      result = ArticleOpportunityAnalyzer.from_snapshots(business: @business, apply: true)
      assert_equal "apply", result.mode
      assert_equal result.created_count, result.candidate_ids.size
      assert_equal result.created_count, ActionCandidate.count - before_count

      candidate = ActionCandidate.last
      assert_equal "archived", candidate.status
      assert_equal "business_analyzer", candidate.generation_source
      assert_equal true, candidate.metadata["experimental_only"]
      assert_equal false, candidate.metadata["today_connected"]
      assert_equal false, candidate.metadata["codex_connected"]
      assert_equal "article_opportunity_analyzer_snapshot_v1", candidate.metadata["value_model_name"]
      assert candidate.metadata["search_demand_score"].present?
      assert candidate.metadata["improvement_potential_score"].present?
      assert candidate.metadata["expected_improvement_score"].present?
      assert candidate.metadata["success_probability"].present?
      assert candidate.metadata["estimated_work_hours"].present?
      assert candidate.metadata["business_value"].present?
    end

    test "compare with legacy returns rank differences" do
      create_article_snapshot(article_id: 104, path: "/articles/suelog-comparison")
      @business.action_candidates.create!(
        title: "吸えログ比較の記事を更新する",
        action_type: "article_update",
        generation_source: "business_analyzer",
        status: "proposal",
        immediate_value_yen: 100,
        final_expected_value_yen: 100,
        success_probability: 0.5,
        metadata: {
          "target_url" => "/articles/suelog-comparison",
          "value_model_name" => "article_opportunity_analyzer"
        }
      )

      result = ArticleOpportunityAnalyzer.compare_with_legacy(business: @business)

      assert_equal 1, result.legacy_article_count
      assert_equal 1, result.new_article_count
      assert_operator result.match_rate, :>, 0
      assert result.rank_differences.any?
    end

    test "prioritizes improvement headroom over current popularity" do
      create_article_snapshot(
        article_id: 201,
        path: "/articles/umeda-private-smoking",
        title: "梅田 個室 喫煙",
        gsc: { "available" => true, "impressions" => 2_500, "clicks" => 15, "ctr" => 0.006, "average_position" => 13, "query_count" => 6 },
        ga4: { "available" => true, "pageviews" => 600, "active_users" => 160, "sessions" => 260, "engagement_seconds" => 20_000 },
        shop_click: { "available" => true, "total_clicks" => 2 },
        article: { "title" => "梅田 個室 喫煙", "word_count" => 1_100, "internal_link_count" => 0, "shop_count" => 4, "verified_shop_count" => 2 }
      )
      create_article_snapshot(
        article_id: 202,
        path: "/articles/vape",
        title: "VAPE",
        gsc: { "available" => true, "impressions" => 20, "clicks" => 1, "ctr" => 0.05, "average_position" => 8, "query_count" => 1 },
        ga4: { "available" => true, "pageviews" => 1_800, "active_users" => 1_000, "sessions" => 1_100, "engagement_seconds" => 180_000 },
        shop_click: { "available" => true, "total_clicks" => 120 },
        article: { "title" => "VAPE", "word_count" => 4_000, "internal_link_count" => 6, "shop_count" => 10, "verified_shop_count" => 10 }
      )

      results = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results
      by_path = results.index_by(&:normalized_path)

      assert_operator by_path["/articles/umeda-private-smoking"].opportunity_score, :>, by_path["/articles/vape"].opportunity_score
      assert_operator by_path["/articles/umeda-private-smoking"].score_breakdown["ctr_opportunity"], :>, 0
      assert_equal 0, by_path["/articles/vape"].score_breakdown["seo_opportunity"]
    end

    test "high pv alone does not create pv opportunity without weakness" do
      create_article_snapshot(
        article_id: 203,
        path: "/articles/popular-complete",
        ga4: { "available" => true, "pageviews" => 2_000, "active_users" => 1_000, "sessions" => 1_200, "engagement_seconds" => 200_000 },
        shop_click: { "available" => true, "total_clicks" => 120 },
        article: { "title" => "完成記事", "word_count" => 4_000, "internal_link_count" => 5, "shop_count" => 10, "verified_shop_count" => 10 }
      )

      article_result = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results.first

      assert_operator article_result.score_breakdown["pv_opportunity"], :<, 5
      assert_operator article_result.score_breakdown["content_opportunity"], :<, 3
    end

    test "ranks by expected improvement score instead of opportunity score alone" do
      create_article_snapshot(
        article_id: 204,
        path: "/articles/short-ctr-win",
        title: "短時間CTR改善",
        gsc: { "available" => true, "impressions" => 4_000, "clicks" => 20, "ctr" => 0.005, "average_position" => 12, "query_count" => 5 },
        ga4: { "available" => true, "pageviews" => 400, "active_users" => 160, "sessions" => 220, "engagement_seconds" => 18_000 },
        shop_click: { "available" => true, "total_clicks" => 20 },
        article: { "title" => "短時間CTR改善", "word_count" => 3_000, "internal_link_count" => 4, "shop_count" => 8, "verified_shop_count" => 8 },
        learning: { "improvement_count" => 4, "improvement_success_count" => 4 }
      )
      create_article_snapshot(
        article_id: 205,
        path: "/articles/large-content-work",
        title: "大型本文更新",
        gsc: { "available" => true, "impressions" => 500, "clicks" => 15, "ctr" => 0.03, "average_position" => 9, "query_count" => 2 },
        ga4: { "available" => true, "pageviews" => 300, "active_users" => 120, "sessions" => 180, "engagement_seconds" => 8_000 },
        shop_click: { "available" => true, "total_clicks" => 0 },
        article: { "title" => "大型本文更新", "word_count" => 500, "internal_link_count" => 0, "shop_count" => 2, "verified_shop_count" => 1 },
        learning: { "improvement_count" => 4, "improvement_success_count" => 2 }
      )

      results = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results
      first = results.first
      large_work = results.detect { |row| row.normalized_path == "/articles/large-content-work" }

      assert_equal "/articles/short-ctr-win", first.normalized_path
      assert_operator first.expected_improvement_score, :>, large_work.expected_improvement_score
      assert_operator first.search_demand_score, :>, large_work.search_demand_score
      assert_operator first.improvement_potential_score, :>, 0
      assert_operator large_work.opportunity_score, :>, 0
      assert_includes first.metadata["ranking_reason"], "expected_improvement_score"
    end

    test "search demand prevents low demand internal link gaps from dominating" do
      create_article_snapshot(
        article_id: 206,
        path: "/articles/high-demand-ctr-gap",
        title: "高需要CTR改善",
        gsc: { "available" => true, "impressions" => 2_400, "clicks" => 17, "ctr" => 0.007, "average_position" => 13, "query_count" => 6 },
        ga4: { "available" => true, "pageviews" => 650, "active_users" => 210, "sessions" => 260, "engagement_seconds" => 25_000 },
        shop_click: { "available" => true, "total_clicks" => 8 },
        article: { "title" => "高需要CTR改善", "word_count" => 2_800, "internal_link_count" => 3, "shop_count" => 8, "verified_shop_count" => 8 },
        learning: { "improvement_count" => 2, "improvement_success_count" => 1 }
      )
      create_article_snapshot(
        article_id: 207,
        path: "/articles/the-single",
        title: "THE SINGLE",
        gsc: { "available" => true, "impressions" => 30, "clicks" => 1, "ctr" => 0.033, "average_position" => 55, "query_count" => 1 },
        ga4: { "available" => true, "pageviews" => 80, "active_users" => 30, "sessions" => 45, "engagement_seconds" => 2_000 },
        shop_click: { "available" => true, "total_clicks" => 0 },
        article: { "title" => "THE SINGLE", "word_count" => 900, "internal_link_count" => 0, "shop_count" => 2, "verified_shop_count" => 1 },
        learning: { "improvement_count" => 2, "improvement_success_count" => 2 }
      )

      results = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results
      high_demand = results.detect { |row| row.normalized_path == "/articles/high-demand-ctr-gap" }
      low_demand = results.detect { |row| row.normalized_path == "/articles/the-single" }

      assert_operator high_demand.search_demand_score, :>, low_demand.search_demand_score
      assert_operator high_demand.expected_improvement_score, :>, low_demand.expected_improvement_score
      assert_includes low_demand.metadata["ranking_reason"], "検索需要が小さい"
    end

    test "seo and ctr opportunities drive improvement potential" do
      create_article_snapshot(
        article_id: 208,
        path: "/articles/rank-12-low-ctr",
        title: "順位12位CTR低い",
        gsc: { "available" => true, "impressions" => 3_000, "clicks" => 21, "ctr" => 0.007, "average_position" => 12, "query_count" => 7 },
        ga4: { "available" => true, "pageviews" => 700, "active_users" => 240, "sessions" => 300, "engagement_seconds" => 35_000 },
        shop_click: { "available" => true, "total_clicks" => 12 },
        article: { "title" => "順位12位CTR低い", "word_count" => 2_700, "internal_link_count" => 3, "shop_count" => 8, "verified_shop_count" => 8 },
        learning: { "improvement_count" => 3, "improvement_success_count" => 2 }
      )
      create_article_snapshot(
        article_id: 209,
        path: "/articles/demand-without-gap",
        title: "需要はあるが改善余地小",
        gsc: { "available" => true, "impressions" => 3_200, "clicks" => 160, "ctr" => 0.05, "average_position" => 3, "query_count" => 7 },
        ga4: { "available" => true, "pageviews" => 800, "active_users" => 420, "sessions" => 520, "engagement_seconds" => 80_000 },
        shop_click: { "available" => true, "total_clicks" => 80 },
        article: { "title" => "需要はあるが改善余地小", "word_count" => 4_000, "internal_link_count" => 5, "shop_count" => 10, "verified_shop_count" => 10 },
        learning: { "improvement_count" => 3, "improvement_success_count" => 2 }
      )

      results = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results
      high_gap = results.detect { |row| row.normalized_path == "/articles/rank-12-low-ctr" }
      low_gap = results.detect { |row| row.normalized_path == "/articles/demand-without-gap" }

      assert_operator high_gap.score_breakdown["seo_opportunity"], :>, 0
      assert_operator high_gap.score_breakdown["ctr_opportunity"], :>, 0
      assert_operator high_gap.improvement_potential_score, :>, low_gap.improvement_potential_score
      assert_operator high_gap.expected_improvement_score, :>, low_gap.expected_improvement_score
    end

    test "uses gsc aliases when average_position and available are missing" do
      create_article_snapshot(
        article_id: 210,
        path: "/articles/alias-gsc",
        title: "GSC別名",
        gsc: { "impressions" => 2_000, "clicks" => 10, "current_ctr" => 0.005, "position" => 14, "queries_count" => 5 },
        ga4: { "pageviews" => 300, "activeUsers" => 120, "sessions" => 150, "userEngagementDuration" => 12_000 },
        shop_click: { "total_clicks" => 3 },
        article: { "title" => "GSC別名", "word_count" => 2_400, "internal_link_count" => 3, "shop_count" => 8, "verified_shop_count" => 8 }
      )

      result = ArticleOpportunityAnalyzer.from_snapshots(business: @business).article_results.first

      assert_operator result.score_breakdown["seo_opportunity"], :>, 0
      assert_operator result.score_breakdown["ctr_opportunity"], :>, 0
      assert_equal "順位11〜20・表示あり・CTR改善余地あり", result.metadata.dig("score_diagnostics", "seo_reason")
      assert_equal "表示あり・CTR改善余地あり", result.metadata.dig("score_diagnostics", "ctr_reason")
    end

    private

    def create_article_snapshot(article_id:, path:, title: "記事", gsc: nil, ga4: nil, shop_click: nil, article: nil, learning: nil)
      AicooDataSnapshot.create!(
        source_type: "article_analytics",
        source_id: article_id,
        captured_at: Time.current,
        payload: {
          "source_type" => "article_analytics",
          "business_id" => @business.id,
          "article_id" => article_id,
          "normalized_path" => path,
          "slug" => path.split("/").last,
          "gsc" => gsc || { "available" => true, "impressions" => 2_000, "clicks" => 10, "ctr" => 0.005, "average_position" => 18, "query_count" => 2 },
          "ga4" => ga4 || { "available" => true, "pageviews" => 300, "active_users" => 100, "sessions" => 140, "engagement_seconds" => 12_000 },
          "shop_click" => shop_click || { "available" => true, "total_clicks" => 0, "article_shop_clicks" => 0 },
          "article" => article || { "title" => title, "word_count" => 800, "internal_link_count" => 0, "shop_count" => 2, "verified_shop_count" => 1 },
          "learning" => learning || { "improvement_count" => 0, "improvement_success_count" => 0 },
          "snapshot_status" => "active"
        }
      )
    end
  end
end

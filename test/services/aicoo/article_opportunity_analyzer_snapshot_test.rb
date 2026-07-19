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
      assert article_result.score_breakdown.key?("seo_opportunity")
      assert article_result.score_breakdown.key?("learning_confidence")
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

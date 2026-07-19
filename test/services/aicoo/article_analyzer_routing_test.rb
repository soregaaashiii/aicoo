require "test_helper"

module Aicoo
  class ArticleAnalyzerRoutingTest < ActiveSupport::TestCase
    test "suelog uses article opportunity analyzer and disables legacy generation" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")

      routing = ArticleAnalyzerRouting.call(business:)

      assert_equal ArticleOpportunityDailyRun::MODEL_NAME, routing.active_analyzer
      assert_equal true, routing.new_analyzer_enabled
      assert_equal false, routing.legacy_generation_enabled
      assert_equal true, routing.legacy_article_analyzer_skipped?
      assert_equal "new_analyzer_active", routing.routing_reason
      assert_equal true, routing.daily_run_metadata["legacy_article_analyzer_skipped"]
    end

    test "non suelog business keeps legacy generation enabled" do
      business = businesses(:cards)

      routing = ArticleAnalyzerRouting.call(business:)

      assert_equal "legacy_expected_value_analyzer", routing.active_analyzer
      assert_equal false, routing.new_analyzer_enabled
      assert_equal true, routing.legacy_generation_enabled
      assert_equal false, routing.legacy_article_analyzer_skipped?
    end

    test "new and legacy candidates are not mixed" do
      business = businesses(:suelog)
      business.update!(project_key: "suelog", repository_name: "suelog")
      business.action_candidates.create!(
        title: "旧記事候補",
        action_type: "new_article_candidate",
        generation_source: "business_analyzer",
        status: "proposal",
        metadata: {
          "suelog_site_insights" => true,
          "query" => "梅田 喫煙 カフェ"
        }
      )
      business.action_candidates.create!(
        title: "新記事候補",
        action_type: "article_update",
        generation_source: "business_analyzer",
        status: "proposal",
        metadata: {
          "value_model_name" => ArticleOpportunityDailyRun::MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => 1
        }
      )

      routing = ArticleAnalyzerRouting.call(business:)

      assert_equal 1, routing.today_new_candidate_count
      assert_equal 1, routing.today_legacy_candidate_count
      assert_equal "article_opportunity_analyzer", routing.fallback_source
    end
  end
end

require "test_helper"

module Aicoo
  module LpIntegration
    class BusinessLandingPagePlannerTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "Planner test",
          description: "LP planner test business",
          status: "launched",
          business_type: "saas"
        )
        @campaign = @business.business_campaigns.create!(
          name: "SEO",
          campaign_type: "seo",
          status: "active",
          target_conversions: 10
        )
        @landing_page = LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "Current SEO LP",
          source_type: "public_url",
          url: "https://lp.example.com/current",
          ga4_page_path: "/current",
          public_status: "published"
        )
        @landing_page.update!(metadata: @landing_page.metadata.to_h.merge(
          "creation_purpose" => "seo",
          "expected_profit_yen" => 10_000,
          "expected_cv" => 2
        ))
      end

      test "plans missing landing pages from campaign target and ranks only by expected profit yen" do
        result = BusinessLandingPagePlanner.new(
          @business,
          campaigns: @business.business_campaigns.active.includes(:landing_pages).to_a,
          external_landing_pages: @business.business_prototypes.active.external_landing_pages.to_a,
          action_candidates: @business.action_candidates.to_a,
          search_query_count: 0
        ).call
        seo = result.recommendations.find { |row| row.fetch("purpose") == "seo" }

        assert_equal 1, seo.fetch("existing_count")
        assert_equal 5, seo.fetch("recommended_count")
        assert_equal 4, seo.fetch("missing_count")
        assert_equal 40_000, seo.fetch("expected_profit_yen")
        assert_equal "campaign_conversion_target", seo.fetch("count_source")
        assert_equal result.recommendations.sort_by { |row| -row.fetch("expected_profit_yen") },
          result.recommendations
      end

      test "persist stores planner facts in business metadata without adding measurement settings" do
        assert_no_difference [ "AicooAnalyticsSite.count", "BusinessDataSourceSetting.count" ] do
          BusinessLandingPagePlanner.new(@business).call(persist: true)
        end

        planner = @business.reload.metadata.to_h.fetch("lp_improvement_planner")
        assert_equal "expected_profit_yen", planner.fetch("ranking_metric")
        assert planner.fetch("total_missing_count").positive?
      end

      test "ranks lp additions and measured improvements together by expected profit yen" do
        candidate = @business.action_candidates.create!(
          title: "Current SEO LPのCTAを改善",
          action_type: "ui_improvement",
          generation_source: "lp_learning",
          immediate_value_yen: 80_000,
          success_probability: 1,
          metadata: { "landing_page_id" => @landing_page.id }
        )

        result = BusinessLandingPagePlanner.new(@business).call

        assert_equal "improve_landing_page", result.ranked_actions.first.fetch("planner_action")
        assert_equal candidate.id, result.ranked_actions.first.fetch("action_candidate_id")
        assert_equal result.ranked_actions.sort_by { |row| -row.fetch("expected_profit_yen").to_i },
          result.ranked_actions
      end
    end
  end
end

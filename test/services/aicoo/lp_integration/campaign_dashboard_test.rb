require "test_helper"

module Aicoo
  module LpIntegration
    class CampaignDashboardTest < ActiveSupport::TestCase
      test "campaign ranking uses expected profit yen and aggregates landing page facts" do
        business = Business.create!(name: "Campaign集計", status: "launched", business_type: "landing_page")
        seo = business.business_campaigns.create!(name: "SEO", campaign_type: "seo")
        ads = business.business_campaigns.create!(name: "広告", campaign_type: "google_ads")
        seo_lp = landing_page(business, seo, "SEO LP", 2_000, 4, 30_000)
        ads_lp = landing_page(business, ads, "広告 LP", 5_000, 20, 10_000)

        rows = CampaignDashboard.new(business).call

        assert_equal [ seo, ads ], rows.map { |row| row.fetch(:campaign) }
        assert_equal [ 1, 2 ], rows.map { |row| row.fetch(:rank) }
        assert_equal 30_000, rows.first.fetch(:expected_profit_yen)
        assert_equal 2_000, rows.first.fetch(:pageviews)
        assert_equal 4, rows.first.fetch(:conversions)
        assert_equal seo_lp, rows.first.fetch(:landing_pages).first.fetch(:landing_page)
        assert_equal 1, rows.first.fetch(:landing_pages).first.fetch(:rank)
        assert_equal ads_lp, rows.second.fetch(:landing_pages).first.fetch(:landing_page)
      end

      test "new candidate expected profit is not hidden by an earlier daily snapshot" do
        business = Business.create!(name: "Campaign最新期待値", status: "launched", business_type: "landing_page")
        campaign = business.business_campaigns.create!(name: "SEO", campaign_type: "seo")
        page = landing_page(business, campaign, "SEO LP", 100, 1, 0)
        AicooDataSnapshot.create!(
          source_type: "landing_page_analytics",
          source_id: page.id,
          captured_at: Time.current,
          payload: {
            "business_id" => business.id,
            "landing_page_id" => page.id,
            "evaluation" => { "expected_profit_yen" => 0 }
          }
        )
        business.action_candidates.create!(
          title: "SEO LPのCTAを改善",
          action_type: "ui_improvement",
          generation_source: "lp_learning",
          immediate_value_yen: 40_000,
          success_probability: 1,
          metadata: { "landing_page_id" => page.id }
        )

        row = CampaignDashboard.new(
          business,
          campaigns: business.business_campaigns.active.includes(:landing_pages).to_a,
          external_landing_pages: business.business_prototypes.active.external_landing_pages.to_a,
          action_candidates: business.action_candidates.to_a
        ).call.first.fetch(:landing_pages).first

        assert_equal 40_000, row.fetch(:expected_profit_yen)
      end

      private

      def landing_page(business, campaign, name, pageviews, conversions, expected_profit_yen)
        page = LandingPageRegistry.new(business:).save!(
          campaign_id: campaign.id,
          name:,
          source_type: "public_url",
          url: "https://lp.example.com/#{name.parameterize}",
          public_status: "published"
        )
        page.update!(metadata: page.metadata.to_h.merge(
          "lp_analytics" => {
            "ga4" => { "pageviews" => pageviews, "conversions" => conversions },
            "gsc" => { "impressions" => pageviews * 2, "clicks" => pageviews / 10, "ctr" => 0.05 }
          },
          "expected_profit_yen" => expected_profit_yen
        ))
        page
      end
    end
  end
end

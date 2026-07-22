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

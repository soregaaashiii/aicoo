module Aicoo
  module LpIntegration
    class CampaignDashboard
      def initialize(business)
        @business = business
      end

      def call
        rows = business.business_campaigns.active.includes(:landing_pages).map do |campaign|
          landing_pages = campaign.landing_pages.active.map { |landing_page| landing_page_row(landing_page) }
            .sort_by { |row| [ -row[:expected_profit_yen], row[:landing_page].id ] }
          landing_pages.each_with_index { |row, index| row[:rank] = index + 1 }
          campaign_row(campaign, landing_pages)
        end

        rows.sort_by { |row| [ -row[:expected_profit_yen], row[:campaign].id ] }
          .each_with_index { |row, index| row[:rank] = index + 1 }
      end

      private

      attr_reader :business

      def campaign_row(campaign, landing_pages)
        pageviews = landing_pages.sum { |row| row[:pageviews] }
        conversions = landing_pages.sum { |row| row[:conversions] }
        {
          campaign:,
          landing_pages:,
          lp_count: landing_pages.size,
          pageviews:,
          conversions:,
          conversion_rate: pageviews.positive? ? conversions.fdiv(pageviews) : nil,
          inquiries: landing_pages.sum { |row| row[:inquiries] },
          contracts: landing_pages.sum { |row| row[:contracts] },
          revenue_yen: landing_pages.sum { |row| row[:revenue_yen] },
          expected_profit_yen: landing_pages.sum { |row| row[:expected_profit_yen] },
          expected_hourly_value_yen: landing_pages.sum { |row| row[:expected_hourly_value_yen] },
          improvement_candidate_count: landing_pages.sum { |row| row[:improvement_candidate_count] }
        }
      end

      def landing_page_row(landing_page)
        metadata = landing_page.metadata.to_h
        analytics = metadata.fetch("lp_analytics", {})
        ga4 = analytics.fetch("ga4", {})
        gsc = analytics.fetch("gsc", {})
        candidates = candidates_by_landing_page.fetch(landing_page.id, [])
        history = improvement_history.fetch(landing_page.id, [])
        {
          landing_page:,
          pageviews: ga4["pageviews"].to_i,
          impressions: gsc["impressions"].to_i,
          clicks: gsc["clicks"].to_i,
          ctr: gsc["ctr"],
          average_position: gsc["average_position"],
          conversions: ga4["conversions"].to_i,
          conversion_rate: analytics["current_conversion_rate"] || landing_page.landing_page_conversion_rate,
          inquiries: numeric(analytics["inquiries"] || ga4["inquiries"]),
          deals: numeric(analytics["deals"] || ga4["deals"]),
          contracts: numeric(analytics["contracts"] || ga4["contracts"]),
          revenue_yen: numeric(analytics["revenue_yen"] || ga4["revenue_yen"]),
          expected_profit_yen: numeric(metadata["expected_profit_yen"]),
          expected_cv: numeric(metadata["expected_cv"]),
          expected_hourly_value_yen: numeric(metadata["expected_hourly_value_yen"]),
          improvement_candidate_count: candidates.size,
          last_deploy_at: history.find { |row| row[:deploy_status] == "deployed" }&.dig(:occurred_at),
          improvement_history: history
        }
      end

      def candidates_by_landing_page
        @candidates_by_landing_page ||= business.action_candidates.active_for_ranking.to_a.group_by do |candidate|
          candidate.metadata.to_h["landing_page_id"].to_i
        end
      end

      def improvement_history
        @improvement_history ||= LandingPageImprovementHistory.new(business).call.group_by { |row| row[:landing_page_id] }
      end

      def numeric(value)
        BigDecimal(value.to_s.presence || "0")
      rescue ArgumentError
        0.to_d
      end
    end
  end
end

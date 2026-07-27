module Aicoo
  module LpIntegration
    class CampaignDashboard
      def initialize(business)
        @business = business
      end

      def call
        load_analytics_snapshots
        load_variant_counts
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
        analytics = latest_analytics_by_landing_page.fetch(landing_page.id, metadata.fetch("lp_analytics", {}))
        ga4 = analytics.fetch("ga4", {})
        gsc = analytics.fetch("gsc", {})
        activity = analytics.fetch("activity", {})
        evaluation = analytics.fetch("evaluation", {})
        candidates = candidates_by_landing_page.fetch(landing_page.id, [])
        expected_profit_yen = [
          evaluation["expected_profit_yen"],
          metadata["expected_profit_yen"],
          candidates.filter_map(&:final_expected_value_yen).max
        ].compact.map { |value| numeric(value) }.max || 0.to_d
        history = improvement_history.fetch(landing_page.id, [])
        {
          landing_page:,
          pageviews: ga4["pageviews"].to_i,
          sessions: ga4["sessions"].to_i,
          users: (ga4["users"] || ga4["active_users"]).to_i,
          engagement_seconds: ga4["engagement_seconds"],
          bounce_rate: ga4["bounce_rate"],
          scroll_rate: ga4["scroll_rate"],
          event_count: ga4["event_count"].to_i,
          events: ga4["events"].to_h,
          impressions: gsc["impressions"].to_i,
          clicks: gsc["clicks"].to_i,
          ctr: gsc["ctr"],
          average_position: gsc["average_position"],
          query_count: gsc["query_count"].to_i,
          queries: Array(gsc["queries"]),
          conversions: ga4["conversions"].to_i,
          conversion_rate: evaluation["conversion_rate"] || analytics["current_conversion_rate"] || ga4["conversion_rate"] || landing_page.landing_page_conversion_rate,
          inquiries: numeric(activity["inquiries"] || analytics["inquiries"] || ga4["inquiries"]),
          deals: numeric(activity["deals"] || analytics["deals"] || ga4["deals"]),
          contracts: numeric(activity["contracts"] || analytics["contracts"] || ga4["contracts"]),
          revenue_yen: numeric(activity["revenue_yen"] || analytics["revenue_yen"] || ga4["revenue_yen"]),
          actual_profit_yen: numeric(evaluation["actual_profit_yen"] || activity["profit_yen"]),
          expected_profit_yen:,
          expected_cv: numeric(metadata["expected_cv"]),
          expected_hourly_value_yen: numeric(metadata["expected_hourly_value_yen"]),
          improvement_candidate_count: candidates.size,
          improvement_count: evaluation["improvement_count"].to_i,
          improvement_success_rate: evaluation["improvement_success_rate"],
          last_improvement_at: parse_time(evaluation["last_improvement_at"]),
          learning: analytics["learning"].to_h,
          analyzer_timeline: analytics_history_by_landing_page.fetch(landing_page.id, []),
          variant_count: variant_counts.fetch(landing_page.id, 0),
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

      def load_variant_counts
        @variant_counts = business.business_prototypes.active.external_landing_pages.each_with_object(Hash.new(0)) do |landing_page, counts|
          source_id = landing_page.metadata.to_h["ab_source_landing_page_id"].to_i
          counts[source_id] += 1 if source_id.positive?
        end
      end

      def load_analytics_snapshots
        landing_page_ids = business.business_prototypes.active.external_landing_pages.pluck(:id)
        snapshots = if landing_page_ids.empty?
          []
        else
          AicooDataSnapshot.where(
            source_type: "landing_page_analytics",
            source_id: landing_page_ids,
            captured_at: 120.days.ago..Time.current
          ).recent.to_a
        end
        @latest_analytics_by_landing_page = snapshots.each_with_object({}) do |snapshot, rows|
          rows[snapshot.source_id] ||= snapshot.payload.to_h
        end
        @analytics_history_by_landing_page = snapshots.group_by(&:source_id).transform_values do |rows|
          rows.first(12).map do |snapshot|
            payload = snapshot.payload.to_h
            {
              captured_at: snapshot.captured_at,
              conversion_rate: payload.dig("evaluation", "conversion_rate"),
              ctr: payload.dig("gsc", "ctr"),
              average_position: payload.dig("gsc", "average_position"),
              inquiries: payload.dig("activity", "inquiries").to_i,
              profit_yen: payload.dig("evaluation", "actual_profit_yen").to_i
            }
          end
        end
      end

      def latest_analytics_by_landing_page
        @latest_analytics_by_landing_page || {}
      end

      def analytics_history_by_landing_page
        @analytics_history_by_landing_page || {}
      end

      def variant_counts
        @variant_counts || {}
      end

      def numeric(value)
        BigDecimal(value.to_s.presence || "0")
      rescue ArgumentError
        0.to_d
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end

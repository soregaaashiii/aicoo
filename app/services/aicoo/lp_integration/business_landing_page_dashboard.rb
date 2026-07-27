module Aicoo
  module LpIntegration
    class BusinessLandingPageDashboard
      def initialize(business:, campaign_dashboard:)
        @business = business
        @campaign_dashboard = campaign_dashboard
      end

      def call
        rows = campaign_dashboard.flat_map { |campaign| campaign.fetch(:landing_pages) }
        published = rows.select { |row| row.fetch(:landing_page).landing_page_public_status == "published" }
        sessions = published.sum { |row| row.fetch(:sessions, 0).to_i }
        conversions = published.sum { |row| row.fetch(:conversions, 0).to_i }
        impressions = published.sum { |row| row.fetch(:impressions, 0).to_i }
        clicks = published.sum { |row| row.fetch(:clicks, 0).to_i }
        learnings = rows.filter_map { |row| row[:learning] if row.dig(:learning, "status") == "evaluated" }
        this_week = Time.current.beginning_of_week..Time.current.end_of_week
        histories = rows.flat_map { |row| row.fetch(:improvement_history, []) }
        next_row = published.max_by { |row| [ row.fetch(:expected_profit_yen).to_i, -row.fetch(:landing_page).id ] }

        {
          actual_profit_yen: published.sum { |row| row.fetch(:actual_profit_yen, 0).to_i },
          expected_profit_yen: published.sum { |row| row.fetch(:expected_profit_yen, 0).to_i },
          published_landing_page_count: published.size,
          waiting_improvement_count: business.auto_revision_tasks.where(status: "waiting_approval")
            .where("metadata ->> 'workflow_type' = ?", "external_lp_improvement").count,
          win_rate: learnings.any? ? (learnings.count { |row| row["success"] == true }.to_d / learnings.size).round(4).to_f : nil,
          average_conversion_rate: sessions.positive? ? (conversions.to_d / sessions).round(6).to_f : nil,
          average_ctr: impressions.positive? ? (clicks.to_d / impressions).round(6).to_f : nil,
          inquiry_count: published.sum { |row| row.fetch(:inquiries, 0).to_i },
          weekly_improvement_count: histories.count { |row| row[:occurred_at].present? && row[:occurred_at].in?(this_week) },
          weekly_profit_delta_yen: learnings.sum do |row|
            evaluated_at = Time.zone.parse(row["evaluated_at"].to_s)
            evaluated_at&.in?(this_week) ? row["profit_delta_yen"].to_i : 0
          rescue ArgumentError
            0
          end,
          next_landing_page: next_row&.fetch(:landing_page),
          next_expected_profit_yen: next_row&.fetch(:expected_profit_yen).to_i,
          winning_patterns: LandingPageWinningPatterns.new(business:).call
        }
      end

      private

      attr_reader :business, :campaign_dashboard
    end
  end
end

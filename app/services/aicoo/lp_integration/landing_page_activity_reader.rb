module Aicoo
  module LpIntegration
    class LandingPageActivityReader
      Result = Data.define(:inquiries, :deals, :contracts, :revenue_yen, :profit_yen, :events, :source)

      INQUIRY_PATTERN = /inquir|lead|contact|form_submit|問い合わせ/i
      DEAL_PATTERN = /deal|opportunit|meeting|商談/i
      CONTRACT_PATTERN = /contract|purchase|order_completed|won|契約|成約/i
      REVENUE_KEYS = %w[revenue_yen amount_yen sales_yen revenue amount sales].freeze
      PROFIT_KEYS = %w[profit_yen gross_profit_yen profit gross_profit].freeze

      def initialize(business:, landing_page:, started_at:, ended_at:, activity_logs: nil, revenue_events: nil)
        @business = business
        @landing_page = landing_page
        @started_at = started_at
        @ended_at = ended_at
        @provided_activity_logs = activity_logs
        @provided_revenue_events = revenue_events
      end

      def call
        logs = matching_activity_logs
        events = logs.map(&:activity_type).tally
        revenue_rows = matching_revenue_events
        logged_revenue = logs.sum { |log| numeric_from(log, REVENUE_KEYS) }
        logged_profit = logs.sum { |log| numeric_from(log, PROFIT_KEYS) }
        revenue_yen = if revenue_rows.any?
          revenue_rows.select(&:revenue?).sum(&:amount)
        else
          logged_revenue
        end
        profit_yen = if revenue_rows.any?
          revenue_rows.sum { |row| row.revenue? ? row.amount : -row.amount }
        else
          logged_profit.nonzero? || logged_revenue
        end

        Result.new(
          inquiries: logs.count { |log| log.activity_type.match?(INQUIRY_PATTERN) },
          deals: logs.count { |log| log.activity_type.match?(DEAL_PATTERN) },
          contracts: logs.count { |log| log.activity_type.match?(CONTRACT_PATTERN) },
          revenue_yen:,
          profit_yen:,
          events:,
          source: revenue_rows.any? ? "revenue_events_and_activity" : "business_activity_logs"
        )
      end

      private

      attr_reader :business, :landing_page, :started_at, :ended_at, :provided_activity_logs, :provided_revenue_events

      def matching_activity_logs
        activity_logs.select { |log| in_window?(log.occurred_at) && references_landing_page?(log) }
      end

      def activity_logs
        return Array(provided_activity_logs) if provided_activity_logs

        business.business_activity_logs.where(occurred_at: started_at..ended_at).to_a
      end

      def matching_revenue_events
        revenue_events.select do |event|
          in_date_window?(event.occurred_on) &&
            event.action_candidate&.metadata.to_h&.fetch("landing_page_id", nil).to_i == landing_page.id
        end
      end

      def revenue_events
        return Array(provided_revenue_events) if provided_revenue_events

        business.revenue_events.includes(:action_candidate).where(occurred_on: started_at.to_date..ended_at.to_date).to_a
      end

      def references_landing_page?(log)
        return true if log.resource_type == "BusinessPrototype" && log.resource_id.to_i == landing_page.id

        values = [
          log.metadata,
          log.before_snapshot,
          log.after_snapshot,
          log.changed_fields
        ].flat_map { |source| reference_values(source.to_h.deep_stringify_keys) }
        values.any? { |value| reference_matches?(value) }
      end

      def reference_values(source)
        %w[
          landing_page_id landing_page_prototype_id prototype_id target_record_id
          landing_page_url target_url url page_path ga4_page_path gsc_url
        ].filter_map { |key| source[key] }
      end

      def reference_matches?(value)
        return value.to_i == landing_page.id if value.to_s.match?(/\A\d+\z/)

        normalized = normalize_url_or_path(value)
        normalized.present? && target_references.include?(normalized)
      end

      def target_references
        @target_references ||= [
          landing_page.landing_page_url,
          landing_page.landing_page_cloudflare_url,
          landing_page.landing_page_ga4_path,
          landing_page.metadata.to_h["gsc_url"]
        ].filter_map { |value| normalize_url_or_path(value) }.uniq
      end

      def normalize_url_or_path(value)
        Aicoo::UrlNormalizer.call(value)
      rescue StandardError
        nil
      end

      def numeric_from(log, keys)
        sources = [ log.after_snapshot, log.metadata, log.changed_fields ].map { |value| value.to_h.deep_stringify_keys }
        value = sources.lazy.flat_map { |source| keys.filter_map { |key| source[key] } }.first
        BigDecimal(value.to_s.presence || "0").round
      rescue ArgumentError
        0
      end

      def in_window?(value)
        value.present? && value >= started_at && value <= ended_at
      end

      def in_date_window?(value)
        value.present? && value >= started_at.to_date && value <= ended_at.to_date
      end
    end
  end
end

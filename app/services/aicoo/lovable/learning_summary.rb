module Aicoo
  module Lovable
    class LearningSummary
      def initialize(business:, generation_run:)
        @business = business
        @generation_run = generation_run
      end

      def call(persist: false)
        summary = build_summary
        if persist && published_at
          generation_run.update!(metadata: generation_run.metadata.to_h.merge("learning" => summary))
        end
        summary
      end

      private

      attr_reader :business, :generation_run

      def build_summary
        views = landing_page_events.where(event_type: "view").count
        cta_clicks = landing_page_events.where(event_type: "cta_click").count
        conversions = signups.count
        revenue = revenue_events.sum(:amount)
        cost = publication_candidate&.cost_yen.to_i
        {
          "version" => generation_run.metadata.to_h["version"],
          "measurement_status" => published_at ? "collecting" : "not_published",
          "measurement_started_at" => published_at&.iso8601,
          "pageviews" => views,
          "cta_clicks" => cta_clicks,
          "conversions" => conversions,
          "cta_rate" => ratio(cta_clicks, views),
          "cvr" => ratio(conversions, views),
          "revenue_yen" => revenue,
          "cost_yen" => cost,
          "roi" => cost.positive? ? ((revenue - cost).to_d / cost.to_d).round(4).to_f : nil,
          "ga4" => metric_totals,
          "gsc" => gsc_totals,
          "prompt" => generation_run.prompt,
          "change_request" => generation_run.metadata.to_h["change_request"],
          "refreshed_at" => Time.current.iso8601
        }
      end

      def landing_page
        @landing_page ||= AicooLabLandingPage.find(generation_run.metadata.to_h["landing_page_id"])
      end

      def published_at
        value = generation_run.metadata.to_h.dig("publication", "published_at")
        @published_at ||= Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      def next_published_at
        VersionRepository.new(business:, landing_page:).all.filter_map do |run|
          next if run.id == generation_run.id
          value = run.metadata.to_h.dig("publication", "published_at")
          parsed = Time.zone.parse(value.to_s) if value.present?
          parsed if parsed && published_at && parsed > published_at
        rescue ArgumentError
          nil
        end.min
      end

      def event_range
        published_at...(next_published_at || Time.current)
      end

      def landing_page_events
        return landing_page.aicoo_lab_landing_page_events.none unless published_at

        landing_page.aicoo_lab_landing_page_events.where(occurred_at: event_range)
      end

      def signups
        return landing_page.aicoo_lab_signups.none unless published_at

        landing_page.aicoo_lab_signups.where(created_at: event_range)
      end

      def metric_scope
        return business.business_metric_dailies.none unless published_at

        business.business_metric_dailies.where(recorded_on: published_at.to_date..(next_published_at&.to_date || Date.current))
      end

      def revenue_events
        return business.revenue_events.none unless published_at

        business.revenue_events.where(occurred_on: published_at.to_date..(next_published_at&.to_date || Date.current))
      end

      def metric_totals
        {
          "pageviews" => metric_scope.sum(:pageviews),
          "sessions" => metric_scope.sum(:sessions),
          "engagement_seconds" => metric_scope.sum(:average_engagement_time_seconds),
          "bounce_rate" => metric_scope.average(:bounce_rate)&.to_f
        }
      end

      def gsc_totals
        {
          "impressions" => metric_scope.sum(:impressions),
          "clicks" => metric_scope.sum(:clicks),
          "average_position" => metric_scope.average(:average_position)&.to_f
        }
      end

      def publication_candidate
        id = generation_run.metadata.to_h.dig("publication", "action_candidate_id")
        ActionCandidate.find_by(id:)
      end

      def ratio(numerator, denominator)
        return if denominator.to_i.zero?

        (numerator.to_d / denominator.to_d).round(4).to_f
      end
    end
  end
end

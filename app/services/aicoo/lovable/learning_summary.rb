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
        scrolls = landing_page_events.where(event_type: "scroll").count
        conversions = signups.count
        revenue = revenue_events.sum(:amount)
        cost = publication_candidate&.cost_yen.to_i
        page_analytics = landing_page_analytics
        ga4 = page_analytics.ga4["available"] ? page_analytics.ga4 : metric_totals
        gsc = page_analytics.gsc["available"] ? page_analytics.gsc : gsc_totals
        effective_views = views.positive? ? views : ga4["pageviews"].to_i
        confidence = measurement_confidence(effective_views)
        {
          "version" => generation_run.metadata.to_h["version"],
          "measurement_status" => measurement_status(effective_views),
          "measurement_started_at" => published_at&.iso8601,
          "measurement_ended_at" => next_published_at&.iso8601,
          "measurement_days" => measurement_days,
          "pageviews" => effective_views,
          "direct_pageviews" => views,
          "pageview_source" => views.positive? ? "landing_page_events" : (ga4["available"] ? "ga4" : "unavailable"),
          "landing_page_events_available" => views.positive?,
          "cta_clicks" => cta_clicks,
          "scrolls" => scrolls,
          "conversions" => conversions,
          "cta_rate" => ratio(cta_clicks, views),
          "cvr" => ratio(conversions, views),
          "form_submit_rate" => ratio(conversions, cta_clicks),
          "scroll_rate" => ratio(scrolls, views),
          "revenue_yen" => revenue,
          "cost_yen" => cost,
          "roi" => cost.positive? ? ((revenue - cost).to_d / cost.to_d).round(4).to_f : nil,
          "expected_profit_yen" => publication_candidate&.final_expected_value_yen || publication_candidate&.expected_profit_yen,
          "confidence" => confidence,
          "analysis_ready" => effective_views >= LandingPageLearningComparison::MIN_PAGEVIEWS,
          "ga4" => ga4,
          "gsc" => gsc,
          "metrics" => {
            "cv" => conversions,
            "cvr" => ratio(conversions, views),
            "cta_clicks" => cta_clicks,
            "cta_click_rate" => ratio(cta_clicks, views),
            "form_submit_rate" => ratio(conversions, cta_clicks),
            "bounce_rate" => ga4["bounce_rate"],
            "engagement_seconds" => ga4["engagement_seconds"],
            "scroll_rate" => ratio(scrolls, views),
            "gsc_clicks_per_day" => per_day(gsc["clicks"]),
            "gsc_impressions_per_day" => per_day(gsc["impressions"]),
            "roi" => cost.positive? ? ((revenue - cost).to_d / cost.to_d).round(4).to_f : nil,
            "expected_profit_yen" => publication_candidate&.final_expected_value_yen || publication_candidate&.expected_profit_yen
          },
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
        sessions = metric_scope.sum(:sessions)
        engagement_total = metric_scope.sum(Arel.sql("average_engagement_time_seconds * sessions"))
        {
          "pageviews" => metric_scope.sum(:pageviews),
          "active_users" => metric_scope.sum(:users),
          "sessions" => sessions,
          "engagement_seconds" => sessions.positive? ? (engagement_total.to_d / sessions).round(2).to_f : nil,
          "event_count" => metric_scope.sum(:event_count),
          "landing_page_views" => metric_scope.sum(:pageviews),
          "bounce_rate" => weighted_average(:bounce_rate, :sessions),
          "source" => "business_metric_daily",
          "scope" => "business_fallback",
          "missing_reason" => page_analytics.ga4["missing_reason"]
        }
      end

      def gsc_totals
        {
          "impressions" => metric_scope.sum(:impressions),
          "clicks" => metric_scope.sum(:clicks),
          "average_position" => weighted_average(:average_position, :impressions),
          "source" => "business_metric_daily",
          "scope" => "business_fallback",
          "missing_reason" => page_analytics.gsc["missing_reason"]
        }
      end

      def landing_page_analytics
        @landing_page_analytics ||= LandingPageAnalyticsReader.new(
          business:,
          generation_run:,
          landing_page:,
          started_at: published_at,
          ended_at: next_published_at || Time.current
        ).call
      end

      def publication_candidate
        id = generation_run.metadata.to_h.dig("publication", "action_candidate_id")
        ActionCandidate.find_by(id:)
      end

      def ratio(numerator, denominator)
        return if denominator.to_i.zero?

        (numerator.to_d / denominator.to_d).round(4).to_f
      end

      def measurement_days
        return 0 unless published_at

        [ ((next_published_at || Time.current).to_date - published_at.to_date).to_i + 1, 1 ].max
      end

      def per_day(value)
        return if measurement_days.zero?

        (value.to_d / measurement_days).round(4).to_f
      end

      def weighted_average(value_column, weight_column)
        weight = metric_scope.sum(weight_column)
        return if weight.to_i.zero?

        total = metric_scope.sum(Arel.sql("#{value_column} * #{weight_column}"))
        (total.to_d / weight.to_d).round(4).to_f
      end

      def measurement_status(views)
        return "not_published" unless published_at
        return "ready" if views >= LandingPageLearningComparison::MIN_PAGEVIEWS

        "collecting"
      end

      def measurement_confidence(views)
        return 0.0 unless published_at
        return 0.9 if views >= 500
        return 0.75 if views >= 200
        return 0.6 if views >= 50
        return 0.45 if views >= LandingPageLearningComparison::MIN_PAGEVIEWS

        (views.to_f / LandingPageLearningComparison::MIN_PAGEVIEWS * 0.4).round(2)
      end
    end
  end
end

module Aicoo
  class LpEvaluationSummary
    Row = Data.define(
      :landing_page,
      :pv,
      :cta_clicks,
      :cv,
      :cvr,
      :gsc_clicks,
      :gsc_impressions,
      :trend_7d,
      :trend_label,
      :verdict,
      :recommendation,
      :improvement_count
    ) do
      def promotable?
        verdict.in?(%w[promising strong])
      end
    end

    Candidate = Data.define(:business, :landing_page, :summary)

    def self.for_business(business)
      new(business).call
    end

    def self.promotion_candidates(limit: 8)
      Business.real_businesses
              .where.not(lifecycle_stage: %w[mvp production scaling archived])
              .includes(:aicoo_lab_landing_pages, :business_metric_dailies, :business_activity_logs)
              .find_each
              .filter_map do |business|
                row = for_business(business).select(&:promotable?).max_by { |summary| [ verdict_rank(summary.verdict), summary.cv, summary.cta_clicks, summary.pv ] }
                row ? Candidate.new(business:, landing_page: row.landing_page, summary: row) : nil
              end
              .sort_by { |candidate| [ -verdict_rank(candidate.summary.verdict), -candidate.summary.cv, -candidate.summary.cta_clicks, candidate.business.name ] }
              .first(limit)
    end

    def self.verdict_rank(verdict)
      { "strong" => 3, "promising" => 2, "poor" => 1 }.fetch(verdict, 0)
    end

    def initialize(business)
      @business = business
    end

    def call
      landing_pages.map { |landing_page| build_row(landing_page) }
    end

    private

    attr_reader :business

    def landing_pages
      business.aicoo_lab_landing_pages.order(updated_at: :desc)
    end

    def build_row(landing_page)
      pv = landing_page.view_count
      cta_clicks = landing_page.cta_click_count
      cv = landing_page.signup_count
      cvr = pv.positive? ? (cv.to_d / pv.to_d) : 0.to_d
      trend_7d = seven_day_trend(landing_page)
      verdict = verdict_for(pv:, cta_clicks:, cv:, cvr:)

      Row.new(
        landing_page:,
        pv:,
        cta_clicks:,
        cv:,
        cvr:,
        gsc_clicks: gsc_clicks,
        gsc_impressions: gsc_impressions,
        trend_7d:,
        trend_label: trend_label(trend_7d),
        verdict:,
        recommendation: recommendation_for(verdict),
        improvement_count: improvement_count(landing_page)
      )
    end

    def recent_metrics
      @recent_metrics ||= business.business_metric_dailies.where(recorded_on: 30.days.ago.to_date..Date.current)
    end

    def gsc_clicks
      @gsc_clicks ||= recent_metrics.sum(:clicks)
    end

    def gsc_impressions
      @gsc_impressions ||= recent_metrics.sum(:impressions)
    end

    def seven_day_trend(landing_page)
      current = landing_page.aicoo_lab_landing_page_events.where(event_type: "view", occurred_at: 7.days.ago..Time.current).count
      previous = landing_page.aicoo_lab_landing_page_events.where(event_type: "view", occurred_at: 14.days.ago...7.days.ago).count
      return 0 if current.zero? && previous.zero?
      return 100 if previous.zero?

      (((current - previous).to_d / previous.to_d) * 100).round
    end

    def trend_label(trend)
      return "上昇 +#{trend}%" if trend.positive?
      return "低下 #{trend}%" if trend.negative?

      "横ばい"
    end

    def verdict_for(pv:, cta_clicks:, cv:, cvr:)
      return "strong" if cv >= 3 || cvr >= 0.05 || cta_clicks >= 10
      return "promising" if cv >= 1 || cta_clicks >= 3 || pv >= 100

      "poor"
    end

    def recommendation_for(verdict)
      case verdict
      when "strong"
        "MVP開発へ進める価値が高い反応です。最小機能と課金導線を設計してください。"
      when "promising"
        "MVP候補です。不足情報を埋めて小さく開発着手できます。"
      else
        "LP訴求、CTA、集客導線を改善して反応を増やしてください。"
      end
    end

    def improvement_count(landing_page)
      business.business_activity_logs.where(resource_type: "AicooLabLandingPage", resource_id: landing_page.id.to_s).count
    end
  end
end

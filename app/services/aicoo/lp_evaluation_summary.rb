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

    def self.for_business(business, landing_pages: nil, metrics: nil)
      new(business, landing_pages:, metrics:).call
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

    def initialize(business, landing_pages: nil, metrics: nil)
      @business = business
      @provided_landing_pages = landing_pages
      @provided_metrics = metrics
    end

    def call
      prepare_counts
      landing_pages.map { |landing_page| build_row(landing_page) }
    end

    private

    attr_reader :business, :provided_landing_pages, :provided_metrics

    def landing_pages
      @landing_pages ||= provided_landing_pages || business.aicoo_lab_landing_pages.order(updated_at: :desc).to_a
    end

    def build_row(landing_page)
      pv = event_counts.fetch([ landing_page.id, "view" ], 0)
      cta_clicks = event_counts.fetch([ landing_page.id, "cta_click" ], 0)
      cv = signup_counts.fetch(landing_page.id, 0)
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
      metric_totals.fetch("clicks", 0)
    end

    def gsc_impressions
      metric_totals.fetch("impressions", 0)
    end

    def seven_day_trend(landing_page)
      current = current_view_counts.fetch(landing_page.id, 0)
      previous = previous_view_counts.fetch(landing_page.id, 0)
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
      improvement_counts.fetch(landing_page.id.to_s, 0)
    end

    def prepare_counts
      ids = landing_pages.filter_map(&:id)
      @event_counts = AicooLabLandingPageEvent.where(aicoo_lab_landing_page_id: ids)
        .group(:aicoo_lab_landing_page_id, :event_type)
        .count
      @signup_counts = AicooLabSignup.where(aicoo_lab_landing_page_id: ids)
        .group(:aicoo_lab_landing_page_id)
        .count

      now = Time.current
      seven_days_ago = 7.days.ago
      @current_view_counts = view_counts_for(ids, seven_days_ago..now)
      @previous_view_counts = view_counts_for(ids, 14.days.ago...seven_days_ago)
      @improvement_counts = business.business_activity_logs
        .where(resource_type: "AicooLabLandingPage", resource_id: ids.map(&:to_s))
        .group(:resource_id)
        .count
      @metric_totals = if provided_metrics
        rows = Array(provided_metrics).select { |metric| metric.recorded_on.in?(30.days.ago.to_date..Date.current) }
        { "clicks" => rows.sum { |metric| metric.clicks.to_i }, "impressions" => rows.sum { |metric| metric.impressions.to_i } }
      else
        recent_metrics.pick(
          Arel.sql("COALESCE(SUM(clicks), 0)"),
          Arel.sql("COALESCE(SUM(impressions), 0)")
        ).then { |clicks, impressions| { "clicks" => clicks, "impressions" => impressions } }
      end
    end

    attr_reader :event_counts,
                :signup_counts,
                :current_view_counts,
                :previous_view_counts,
                :improvement_counts,
                :metric_totals

    def view_counts_for(ids, range)
      AicooLabLandingPageEvent
        .where(aicoo_lab_landing_page_id: ids, event_type: "view", occurred_at: range)
        .group(:aicoo_lab_landing_page_id)
        .count
    end
  end
end

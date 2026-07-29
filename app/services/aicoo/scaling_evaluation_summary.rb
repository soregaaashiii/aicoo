module Aicoo
  class ScalingEvaluationSummary
    Result = Data.define(
      :business,
      :monthly_revenue_yen,
      :paid_users,
      :retention_rate,
      :churn_rate,
      :cvr,
      :cac_hypothesis_yen,
      :ltv_hypothesis_yen,
      :gross_profit_yen,
      :trend_7d,
      :trend_30d,
      :trend_7d_label,
      :trend_30d_label,
      :improvement_room,
      :verdict,
      :recommended_investment
    ) do
      def promotable?
        verdict.in?(%w[ready strong])
      end
    end

    Candidate = Data.define(:business, :summary)

    INVESTMENTS = %w[SEO Ads Sales Feature Pricing].freeze

    def self.for_business(business, business_services: nil, metrics: nil, revenue_events: nil)
      new(
        business,
        business_services:,
        metrics:,
        revenue_events:
      ).call
    end

    def self.candidates(limit: 8)
      Business.real_businesses
              .where(lifecycle_stage: "production")
              .includes(:business_services, :business_metric_dailies, :revenue_events, :action_candidates)
              .find_each
              .filter_map do |business|
                summary = for_business(business)
                summary.promotable? ? Candidate.new(business:, summary:) : nil
              end
              .sort_by { |candidate| [ -verdict_rank(candidate.summary.verdict), -candidate.summary.monthly_revenue_yen, candidate.business.name ] }
              .first(limit)
    end

    def self.verdict_rank(verdict)
      { "strong" => 3, "ready" => 2, "not_ready" => 1 }.fetch(verdict, 0)
    end

    def initialize(business, business_services: nil, metrics: nil, revenue_events: nil)
      @business = business
      @provided_business_services = business_services
      @provided_metrics = metrics
      @provided_revenue_events = revenue_events
    end

    def call
      Result.new(
        business:,
        monthly_revenue_yen:,
        paid_users:,
        retention_rate:,
        churn_rate:,
        cvr:,
        cac_hypothesis_yen:,
        ltv_hypothesis_yen:,
        gross_profit_yen:,
        trend_7d: trend_for(7),
        trend_30d: trend_for(30),
        trend_7d_label: trend_label(trend_for(7)),
        trend_30d_label: trend_label(trend_for(30)),
        improvement_room:,
        verdict:,
        recommended_investment:
      )
    end

    private

    attr_reader :business

    def current_month_range
      Date.current.beginning_of_month..Date.current.end_of_month
    end

    def recent_metrics
      @recent_metrics ||= metric_rows(30.days.ago.to_date..Date.current)
    end

    def services_metadata
      services = @provided_business_services || business.business_services.to_a
      @services_metadata ||= services.map { |service| service.metadata.to_h }
    end

    def monthly_revenue_yen
      @monthly_revenue_yen ||= revenue_events_for("revenue", current_month_range).sum(&:amount)
    end

    def monthly_expense_yen
      @monthly_expense_yen ||= revenue_events_for("expense", current_month_range).sum(&:amount)
    end

    def paid_users
      @paid_users ||= metadata_integer("paid_users") || revenue_events_for("revenue", current_month_range).size
    end

    def active_users
      @active_users ||= metadata_integer("active_users") || recent_metrics.sum { |metric| metric.users.to_i }
    end

    def registrations
      @registrations ||= metadata_integer("registrations") || recent_metrics.sum { |metric| metric.conversions.to_i }
    end

    def churn_count
      @churn_count ||= metadata_integer("churn_count") || 0
    end

    def retention_rate
      @retention_rate ||= metadata_decimal("retention_rate") ||
                          (registrations.positive? ? active_users.to_d / registrations.to_d : 0.to_d)
    end

    def churn_rate
      @churn_rate ||= paid_users.positive? ? churn_count.to_d / paid_users.to_d : 0.to_d
    end

    def cvr
      sessions = recent_metrics.sum { |metric| metric.sessions.to_i }
      conversions = recent_metrics.sum { |metric| metric.conversions.to_i }
      @cvr ||= sessions.positive? ? conversions.to_d / sessions.to_d : 0.to_d
    end

    def cac_hypothesis_yen
      @cac_hypothesis_yen ||= metadata_integer("cac_hypothesis_yen") ||
                              (paid_users.positive? ? (monthly_expense_yen.to_d / paid_users.to_d).round : 0)
    end

    def ltv_hypothesis_yen
      @ltv_hypothesis_yen ||= metadata_integer("ltv_hypothesis_yen") ||
                              (paid_users.positive? ? (monthly_revenue_yen.to_d / paid_users.to_d * 6).round : 0)
    end

    def gross_profit_yen
      @gross_profit_yen ||= monthly_revenue_yen - monthly_expense_yen
    end

    def trend_for(days)
      @trends ||= {}
      return @trends[days] if @trends.key?(days)

      current_start = (days - 1).days.ago.to_date
      previous_start = ((days * 2) - 1).days.ago.to_date
      current = revenue_events_for("revenue", current_start..Date.current).sum(&:amount)
      previous = revenue_events_for("revenue", previous_start...current_start).sum(&:amount)
      return @trends[days] = 0 if current.zero? && previous.zero?
      return @trends[days] = 100 if previous.zero?

      @trends[days] = (((current - previous).to_d / previous.to_d) * 100).round
    end

    def trend_label(trend)
      return "上昇 +#{trend}%" if trend.positive?
      return "低下 #{trend}%" if trend.negative?

      "横ばい"
    end

    def improvement_room
      rooms = []
      rooms << "CVR改善" if cvr < 0.05
      rooms << "継続率改善" if retention_rate < 0.5
      rooms << "価格改善" if ltv_hypothesis_yen.positive? && cac_hypothesis_yen.positive? && ltv_hypothesis_yen < cac_hypothesis_yen * 3
      rooms << "獲得チャネル拡大" if gross_profit_yen.positive?
      rooms.presence || [ "既存勝ち筋の横展開" ]
    end

    def verdict
      return "strong" if gross_profit_yen >= 100_000 && paid_users >= 5 && retention_rate >= 0.5 && ltv_hypothesis_yen > cac_hypothesis_yen * 3
      return "ready" if gross_profit_yen.positive? && paid_users.positive? && retention_rate >= 0.3

      "not_ready"
    end

    def recommended_investment
      return "Pricing" if ltv_hypothesis_yen.positive? && cac_hypothesis_yen.positive? && ltv_hypothesis_yen < cac_hypothesis_yen * 3
      return "Feature" if retention_rate < 0.4
      return "SEO" if recent_metrics.sum { |metric| metric.impressions.to_i }.positive? && cvr >= 0.03
      return "Ads" if gross_profit_yen.positive? && ltv_hypothesis_yen > cac_hypothesis_yen * 3
      return "Sales" if paid_users.positive? && monthly_revenue_yen.positive?

      INVESTMENTS.first
    end

    def metadata_integer(key)
      value = services_metadata.filter_map { |metadata| metadata[key] }.first
      value.present? ? value.to_i : nil
    end

    def metadata_decimal(key)
      value = services_metadata.filter_map { |metadata| metadata[key] }.first
      value.present? ? value.to_d : nil
    end

    def metric_rows(range)
      return business.business_metric_dailies.where(recorded_on: range).to_a unless @provided_metrics

      @provided_metrics.select { |metric| metric.recorded_on.in?(range) }
    end

    def revenue_events_for(event_type, range)
      return business.revenue_events.public_send(event_type).where(occurred_on: range).to_a unless @provided_revenue_events

      @provided_revenue_events.select do |event|
        event.event_type == event_type && event.occurred_on.in?(range)
      end
    end
  end
end

module Aicoo
  class MvpEvaluationSummary
    Row = Data.define(
      :business_service,
      :service_url,
      :registrations,
      :active_users,
      :free_users,
      :paid_users,
      :revenue_yen,
      :cvr,
      :retention_rate,
      :churn_count,
      :trend_7d,
      :trend_label,
      :verdict,
      :recommendation
    ) do
      def promotable?
        verdict.in?(%w[promising strong])
      end
    end

    Candidate = Data.define(:business, :business_service, :summary)

    def self.for_business(business)
      new(business).call
    end

    def self.production_candidates(limit: 8)
      Business.real_businesses
              .where(lifecycle_stage: "mvp")
              .includes(:business_services, :business_metric_dailies, :revenue_events)
              .find_each
              .filter_map do |business|
                row = for_business(business).select(&:promotable?).max_by { |summary| [ verdict_rank(summary.verdict), summary.revenue_yen, summary.paid_users, summary.active_users ] }
                row ? Candidate.new(business:, business_service: row.business_service, summary: row) : nil
              end
              .sort_by { |candidate| [ -verdict_rank(candidate.summary.verdict), -candidate.summary.revenue_yen, candidate.business.name ] }
              .first(limit)
    end

    def self.scaling_candidates(limit: 8)
      Business.real_businesses
              .where(lifecycle_stage: "production")
              .includes(:business_services, :business_metric_dailies, :revenue_events)
              .find_each
              .filter_map do |business|
                row = for_business(business).select { |summary| summary.verdict == "strong" }.max_by { |summary| [ summary.revenue_yen, summary.paid_users, summary.active_users ] }
                row ? Candidate.new(business:, business_service: row.business_service, summary: row) : nil
              end
              .sort_by { |candidate| [ -candidate.summary.revenue_yen, candidate.business.name ] }
              .first(limit)
    end

    def self.verdict_rank(verdict)
      { "strong" => 3, "promising" => 2, "poor" => 1 }.fetch(verdict, 0)
    end

    def initialize(business)
      @business = business
    end

    def call
      business.business_services.recent.map { |business_service| build_row(business_service) }
    end

    private

    attr_reader :business

    def build_row(business_service)
      metadata = business_service.metadata.to_h
      registrations = integer_value(metadata["registrations"], metric_sum(:conversions))
      active_users = integer_value(metadata["active_users"], metric_sum(:users))
      paid_users = integer_value(metadata["paid_users"], paid_users_from_revenue)
      free_users = integer_value(metadata["free_users"], [ registrations - paid_users, 0 ].max)
      revenue_yen = integer_value(metadata["revenue_yen"], recent_revenue_yen)
      churn_count = integer_value(metadata["churn_count"], 0)
      cvr = metric_sum(:sessions).positive? ? metric_sum(:conversions).to_d / metric_sum(:sessions).to_d : 0.to_d
      retention_rate = decimal_value(metadata["retention_rate"], registrations.positive? ? active_users.to_d / registrations.to_d : 0.to_d)
      trend_7d = seven_day_trend
      verdict = verdict_for(registrations:, active_users:, paid_users:, revenue_yen:, cvr:, retention_rate:)

      Row.new(
        business_service:,
        service_url: business_service.display_url,
        registrations:,
        active_users:,
        free_users:,
        paid_users:,
        revenue_yen:,
        cvr:,
        retention_rate:,
        churn_count:,
        trend_7d:,
        trend_label: trend_label(trend_7d),
        verdict:,
        recommendation: recommendation_for(verdict)
      )
    end

    def metrics
      @metrics ||= business.business_metric_dailies.where(recorded_on: 30.days.ago.to_date..Date.current)
    end

    def metric_sum(column)
      metrics.sum(column)
    end

    def recent_revenue_yen
      business.revenue_events.revenue.where(occurred_on: 30.days.ago.to_date..Date.current).sum(:amount)
    end

    def paid_users_from_revenue
      business.revenue_events.revenue.where(occurred_on: 30.days.ago.to_date..Date.current).count
    end

    def seven_day_trend
      current = business.business_metric_dailies.where(recorded_on: 6.days.ago.to_date..Date.current).sum(:users)
      previous = business.business_metric_dailies.where(recorded_on: 13.days.ago.to_date...6.days.ago.to_date).sum(:users)
      return 0 if current.zero? && previous.zero?
      return 100 if previous.zero?

      (((current - previous).to_d / previous.to_d) * 100).round
    end

    def trend_label(trend)
      return "上昇 +#{trend}%" if trend.positive?
      return "低下 #{trend}%" if trend.negative?

      "横ばい"
    end

    def verdict_for(registrations:, active_users:, paid_users:, revenue_yen:, cvr:, retention_rate:)
      return "strong" if paid_users >= 3 || revenue_yen >= 30_000 || (registrations >= 10 && retention_rate >= 0.4)
      return "promising" if paid_users >= 1 || revenue_yen.positive? || registrations >= 3 || active_users >= 10 || cvr >= 0.03

      "poor"
    end

    def recommendation_for(verdict)
      case verdict
      when "strong"
        "本番運用へ進める価値が高いMVPです。課金、監視、権限、管理画面を整えてください。"
      when "promising"
        "本番化候補です。不足チェックを埋めてOwner承認でproductionへ進められます。"
      else
        "オンボーディング、CTA、価格、継続導線を改善してMVP利用を増やしてください。"
      end
    end

    def integer_value(value, fallback)
      return fallback.to_i if value.blank?

      value.to_i
    end

    def decimal_value(value, fallback)
      return fallback.to_d if value.blank?

      value.to_d
    end
  end
end

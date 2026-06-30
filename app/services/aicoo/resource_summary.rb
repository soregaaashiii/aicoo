module Aicoo
  class ResourceSummary
    Result = Data.define(
      :business,
      :monthly_cost_yen,
      :estimated_api_cost_yen,
      :estimated_ai_cost_yen,
      :estimated_infra_cost_yen,
      :estimated_maintenance_minutes,
      :error_count,
      :inquiry_count,
      :last_improvement_at,
      :last_reaction_at,
      :last_revenue_on,
      :next_review_on,
      :auto_snooze_recommended,
      :auto_snooze_reason
    )

    def self.for_business(business)
      new(business).call
    end

    def self.default_next_review_on(resource_status)
      case resource_status.to_s
      when "active"
        7.days.from_now.to_date
      when "watch"
        30.days.from_now.to_date
      when "paused"
        60.days.from_now.to_date
      when "archived"
        nil
      else
        14.days.from_now.to_date
      end
    end

    def initialize(business)
      @business = business
    end

    def call
      Result.new(
        business:,
        monthly_cost_yen:,
        estimated_api_cost_yen:,
        estimated_ai_cost_yen:,
        estimated_infra_cost_yen:,
        estimated_maintenance_minutes:,
        error_count:,
        inquiry_count:,
        last_improvement_at:,
        last_reaction_at:,
        last_revenue_on:,
        next_review_on: business.next_review_on,
        auto_snooze_recommended: auto_snooze_recommended?,
        auto_snooze_reason:
      )
    end

    private

    attr_reader :business

    def monthly_cost_yen
      estimated_api_cost_yen + estimated_ai_cost_yen + estimated_infra_cost_yen
    end

    def estimated_api_cost_yen
      business.data_imports.where(created_at: Time.current.beginning_of_month..Time.current).count * 5
    end

    def estimated_ai_cost_yen
      business.auto_revision_tasks.where(created_at: Time.current.beginning_of_month..Time.current).count * 30
    end

    def estimated_infra_cost_yen
      business.business_services.where(status: %w[live production]).exists? ? 1_000 : 0
    end

    def estimated_maintenance_minutes
      (business.action_candidates.active_for_ranking.count * 10) + (error_count * 15) + (inquiry_count * 5)
    end

    def error_count
      @error_count ||= business.business_activity_logs
                             .where(occurred_at: 30.days.ago..Time.current)
                             .where("activity_type LIKE ? OR title LIKE ? OR diff_summary LIKE ?", "%error%", "%失敗%", "%失敗%")
                             .count
    end

    def inquiry_count
      @inquiry_count ||= business.aicoo_lab_landing_pages.joins(:aicoo_lab_signups).where(aicoo_lab_signups: { created_at: 30.days.ago..Time.current }).count
    end

    def last_improvement_at
      @last_improvement_at ||= [
        business.action_results.maximum(:created_at),
        business.auto_revision_tasks.maximum(:created_at),
        business.business_activity_logs.where(activity_type: %w[
          article_updated lp_published lp_updated mvp_promoted production_promoted scaling_promoted
        ]).maximum(:occurred_at)
      ].compact.max
    end

    def last_reaction_at
      @last_reaction_at ||= [
        business.aicoo_lab_landing_pages.joins(:aicoo_lab_landing_page_events).maximum("aicoo_lab_landing_page_events.occurred_at"),
        business.aicoo_lab_landing_pages.joins(:aicoo_lab_signups).maximum("aicoo_lab_signups.created_at"),
        business.business_metric_dailies.maximum(:recorded_on)&.to_time
      ].compact.max
    end

    def last_revenue_on
      @last_revenue_on ||= business.revenue_events.revenue.maximum(:occurred_on)
    end

    def auto_snooze_recommended?
      return false unless business.resource_status == "active"
      return false if error_count.positive? || inquiry_count.positive?
      return false if business.action_candidates.active_for_ranking.exists?
      return false if last_improvement_at && last_improvement_at >= 30.days.ago
      return false if revenue_changed_recently?

      true
    end

    def auto_snooze_reason
      return "30日改善なし・エラーなし・問い合わせなし・改善候補なしのためWatch候補です。" if auto_snooze_recommended?

      "通常確認対象です。"
    end

    def revenue_changed_recently?
      current = business.revenue_events.revenue.where(occurred_on: 30.days.ago.to_date..Date.current).sum(:amount)
      previous = business.revenue_events.revenue.where(occurred_on: 60.days.ago.to_date...30.days.ago.to_date).sum(:amount)
      (current - previous).abs.positive?
    end
  end
end

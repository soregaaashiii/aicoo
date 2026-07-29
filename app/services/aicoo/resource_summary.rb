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

    def self.for_business(
      business,
      active_candidate_count: nil,
      business_services: nil,
      metrics: nil,
      revenue_events: nil
    )
      new(
        business,
        active_candidate_count:,
        business_services:,
        metrics:,
        revenue_events:
      ).call
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

    def initialize(
      business,
      active_candidate_count: nil,
      business_services: nil,
      metrics: nil,
      revenue_events: nil
    )
      @business = business
      @active_candidate_count = active_candidate_count
      @business_services = business_services
      @metrics = metrics
      @revenue_events = revenue_events
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
      if @business_services
        @business_services.any? { |service| service.status.in?(%w[live production]) } ? 1_000 : 0
      else
        business.business_services.where(status: %w[live production]).exists? ? 1_000 : 0
      end
    end

    def estimated_maintenance_minutes
      candidate_count = @active_candidate_count.nil? ? business.action_candidates.active_for_ranking.count : @active_candidate_count
      (candidate_count * 10) + (error_count * 15) + (inquiry_count * 5)
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
        latest_metric_on&.to_time
      ].compact.max
    end

    def last_revenue_on
      @last_revenue_on ||= if @revenue_events
        @revenue_events.select(&:revenue?).filter_map(&:occurred_on).max
      else
        business.revenue_events.revenue.maximum(:occurred_on)
      end
    end

    def auto_snooze_recommended?
      return false unless business.resource_status == "active"
      return false if error_count.positive? || inquiry_count.positive?
      active_candidates = @active_candidate_count.nil? ? business.action_candidates.active_for_ranking.exists? : @active_candidate_count.positive?
      return false if active_candidates
      return false if last_improvement_at && last_improvement_at >= 30.days.ago
      return false if revenue_changed_recently?

      true
    end

    def auto_snooze_reason
      return "30日改善なし・エラーなし・問い合わせなし・改善候補なしのためWatch候補です。" if auto_snooze_recommended?

      "通常確認対象です。"
    end

    def revenue_changed_recently?
      current = revenue_amount(30.days.ago.to_date..Date.current)
      previous = revenue_amount(60.days.ago.to_date...30.days.ago.to_date)
      (current - previous).abs.positive?
    end

    def latest_metric_on
      return @metrics.filter_map(&:recorded_on).max if @metrics

      business.business_metric_dailies.maximum(:recorded_on)
    end

    def revenue_amount(range)
      return business.revenue_events.revenue.where(occurred_on: range).sum(:amount) unless @revenue_events

      @revenue_events.select { |event| event.revenue? && event.occurred_on.in?(range) }.sum(&:amount)
    end
  end
end

module Aicoo
  class AttentionScore
    Result = Data.define(:business, :score, :reasons, :summary, :resource_summary) do
      def needs_attention?
        score.positive? || business.resource_status == "active"
      end
    end

    def self.for_business(business)
      new(business).call
    end

    def self.ranking(limit: nil)
      rows = Business.real_businesses.includes(:action_candidates, :revenue_events, :business_metric_dailies).map do |business|
        for_business(business)
      end.sort_by { |row| [ -row.score, row.business.name ] }

      limit ? rows.first(limit) : rows
    end

    def initialize(business)
      @business = business
      @reasons = []
      @score = 0
      @resource_summary = Aicoo::ResourceSummary.for_business(business)
    end

    def call
      add_revenue_change
      add_errors
      add_inquiries
      add_action_candidates
      add_learning_warnings
      add_daily_run_failures
      add_new_cv
      add_ranking_movement
      apply_resource_status_weight

      Result.new(
        business:,
        score: [ score, 0 ].max,
        reasons: reasons.presence || [ "本日は確認不要" ],
        summary: reasons.first || "安定運用中です。",
        resource_summary:
      )
    end

    private

    attr_reader :business, :reasons, :resource_summary
    attr_accessor :score

    def add(points, reason)
      self.score += points
      reasons << reason
    end

    def add_revenue_change
      current = business.revenue_events.revenue.where(occurred_on: 30.days.ago.to_date..Date.current).sum(:amount)
      previous = business.revenue_events.revenue.where(occurred_on: 60.days.ago.to_date...30.days.ago.to_date).sum(:amount)
      return if current.zero? && previous.zero?

      change = previous.zero? ? 100 : (((current - previous).to_d / previous.to_d) * 100).round
      add(change.abs >= 20 ? 20 : 8, "売上変化 #{change}%")
    end

    def add_errors
      return unless resource_summary.error_count.positive?

      add([ resource_summary.error_count * 10, 40 ].min, "エラー #{resource_summary.error_count}件")
    end

    def add_inquiries
      return unless resource_summary.inquiry_count.positive?

      add([ resource_summary.inquiry_count * 8, 32 ].min, "問い合わせ/CV #{resource_summary.inquiry_count}件")
    end

    def add_action_candidates
      count = business.action_candidates.active_for_ranking.count
      return if count.zero?

      add([ count * 5, 25 ].min, "改善候補 #{count}件")
    end

    def add_learning_warnings
      count = business.business_activity_logs.where(evaluation_status: %w[pending evaluating]).count
      return if count.zero?

      add([ count * 3, 15 ].min, "Learning評価待ち #{count}件")
    end

    def add_daily_run_failures
      failures = AicooDailyRunStep.where(status: "failed").where("metadata ->> 'business_id' = ?", business.id.to_s).count
      return if failures.zero?

      add([ failures * 12, 36 ].min, "Daily Run失敗 #{failures}件")
    end

    def add_new_cv
      count = business.business_metric_dailies.where(recorded_on: 7.days.ago.to_date..Date.current).sum(:conversions)
      return if count.zero?

      add([ count * 4, 24 ].min, "新規CV #{count}件")
    end

    def add_ranking_movement
      recent = business.business_metric_dailies.where(recorded_on: 7.days.ago.to_date..Date.current).average(:average_position).to_d
      previous = business.business_metric_dailies.where(recorded_on: 14.days.ago.to_date...7.days.ago.to_date).average(:average_position).to_d
      return if recent.zero? || previous.zero?

      movement = (recent - previous).abs
      add(10, "順位変動 #{movement.round(1)}") if movement >= 3
    end

    def apply_resource_status_weight
      case business.resource_status
      when "watch"
        self.score = (score * 0.4).round
      when "paused"
        self.score = (score * 0.2).round
      when "archived"
        self.score = 0
      end
    end
  end
end

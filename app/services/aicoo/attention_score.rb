module Aicoo
  class AttentionScore
    Result = Data.define(:business, :score, :reasons, :summary, :resource_summary) do
      def needs_attention?
        score.positive? || business.resource_status == "active"
      end
    end

    def self.for_business(
      business,
      resource_summary: nil,
      active_candidate_count: nil,
      metrics: nil,
      revenue_events: nil
    )
      new(
        business,
        resource_summary:,
        active_candidate_count:,
        metrics:,
        revenue_events:
      ).call
    end

    def self.ranking(limit: nil)
      rows = Business.real_businesses.includes(:action_candidates, :revenue_events, :business_metric_dailies).map do |business|
        for_business(business)
      end.sort_by { |row| [ -row.score, row.business.name ] }

      limit ? rows.first(limit) : rows
    end

    def initialize(
      business,
      resource_summary: nil,
      active_candidate_count: nil,
      metrics: nil,
      revenue_events: nil
    )
      @business = business
      @reasons = []
      @score = 0
      @resource_summary = resource_summary || Aicoo::ResourceSummary.for_business(business)
      @active_candidate_count = active_candidate_count
      @metrics = metrics
      @revenue_events = revenue_events
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
      current = revenue_amount(30.days.ago.to_date..Date.current)
      previous = revenue_amount(60.days.ago.to_date...30.days.ago.to_date)
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
      count = @active_candidate_count.nil? ? business.action_candidates.active_for_ranking.count : @active_candidate_count
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
      count = metric_rows(7.days.ago.to_date..Date.current).sum { |metric| metric.conversions.to_i }
      return if count.zero?

      add([ count * 4, 24 ].min, "新規CV #{count}件")
    end

    def add_ranking_movement
      recent = average_position(7.days.ago.to_date..Date.current)
      previous = average_position(14.days.ago.to_date...7.days.ago.to_date)
      return if recent.zero? || previous.zero?

      movement = (recent - previous).abs
      add(10, "順位変動 #{movement.round(1)}") if movement >= 3
    end

    def metric_rows(range)
      return business.business_metric_dailies.where(recorded_on: range).to_a unless @metrics

      @metrics.select { |metric| metric.recorded_on.in?(range) }
    end

    def average_position(range)
      values = metric_rows(range).filter_map(&:average_position)
      return 0.to_d if values.empty?

      values.sum { |value| value.to_d } / values.size
    end

    def revenue_amount(range)
      return business.revenue_events.revenue.where(occurred_on: range).sum(:amount) unless @revenue_events

      @revenue_events.select { |event| event.revenue? && event.occurred_on.in?(range) }.sum(&:amount)
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

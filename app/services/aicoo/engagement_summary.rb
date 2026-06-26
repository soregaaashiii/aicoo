module Aicoo
  class EngagementSummary
    Result = Data.define(
      :generated_at,
      :business_rows,
      :average_engagement_score,
      :average_engagement_time_seconds,
      :average_views_per_session,
      :average_engagement_rate,
      :average_conversion_rate,
      :low_engagement_business_count,
      :top_businesses,
      :weak_businesses,
      :task_rows
    )
    BusinessRow = Data.define(
      :business,
      :engagement_score,
      :average_engagement_time_seconds,
      :views_per_session,
      :engagement_rate,
      :conversion_rate,
      :sessions,
      :warning
    )

    DEFAULT_DAYS = 30
    LOW_ENGAGEMENT_SCORE = 35.to_d

    def initialize(today: Date.current, days: DEFAULT_DAYS)
      @today = today.to_date
      @days = days
    end

    def call
      rows = business_rows
      Result.new(
        generated_at: Time.current,
        business_rows: rows,
        average_engagement_score: average(rows.map(&:engagement_score)),
        average_engagement_time_seconds: average(rows.map(&:average_engagement_time_seconds)),
        average_views_per_session: average(rows.map(&:views_per_session)),
        average_engagement_rate: average(rows.map(&:engagement_rate)),
        average_conversion_rate: average(rows.map(&:conversion_rate)),
        low_engagement_business_count: rows.count { |row| row.engagement_score.to_d < LOW_ENGAGEMENT_SCORE && row.sessions.to_i.positive? },
        top_businesses: rows.select { |row| row.sessions.to_i.positive? }.sort_by { |row| -row.engagement_score.to_d }.first(5),
        weak_businesses: rows.select { |row| row.sessions.to_i.positive? }.sort_by { |row| row.engagement_score.to_d }.first(5),
        task_rows: task_rows
      )
    end

    private

    attr_reader :today, :days

    def business_rows
      Business.order(:name).map do |business|
        records = metrics_by_business_id.fetch(business.id, [])
        sessions = records.sum(&:sessions)
        row = BusinessRow.new(
          business:,
          engagement_score: average(records.map(&:engagement_score)),
          average_engagement_time_seconds: weighted_average(records, :average_engagement_time_seconds, :sessions),
          views_per_session: ratio(records.sum(&:pageviews), sessions),
          engagement_rate: weighted_average(records, :engagement_rate, :sessions),
          conversion_rate: ratio(records.sum(&:conversions), sessions),
          sessions:,
          warning: warning_for(records, sessions)
        )
        row
      end
    end

    def metrics_by_business_id
      @metrics_by_business_id ||= BusinessMetricDaily.where(recorded_on: date_range).to_a.group_by(&:business_id)
    end

    def task_rows
      BusinessPlaybook.includes(:business).flat_map do |playbook|
        playbook.task_rows.map do |row|
          row.merge("business" => playbook.business.name)
        end
      end.sort_by { |row| -row["average_engagement_delta"].to_d }.first(10)
    end

    def warning_for(records, sessions)
      return "GA4 Engagementデータ不足" if records.empty? || sessions.to_i.zero?

      score = average(records.map(&:engagement_score))
      return "Engagement改善余地あり" if score < LOW_ENGAGEMENT_SCORE

      nil
    end

    def date_range
      @date_range ||= (today - (days - 1))..today
    end

    def weighted_average(records, value_method, weight_method)
      total_weight = records.sum { |record| record.public_send(weight_method).to_d }
      return average(records.map { |record| record.public_send(value_method) }) if total_weight.zero?

      records.sum { |record| record.public_send(value_method).to_d * record.public_send(weight_method).to_d } / total_weight
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_d.zero?

      numerator.to_d / denominator.to_d
    end

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      values.sum / values.size
    end
  end
end

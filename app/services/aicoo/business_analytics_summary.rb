module Aicoo
  class BusinessAnalyticsSummary
    PeriodSummary = Data.define(
      :days,
      :gsc_clicks,
      :gsc_impressions,
      :gsc_ctr,
      :ga4_sessions,
      :ga4_pageviews,
      :revenue_yen,
      :pending_actions,
      :warning_count
    )
    ChartPoint = Data.define(:date, :values)
    Result = Data.define(
      :business,
      :health,
      :last_sync_at,
      :warning_count,
      :warnings,
      :periods,
      :gsc_series,
      :ga4_series,
      :revenue_series,
      :action_series,
      :learning_series,
      :cost_estimates,
      :settings,
      :data_status
    )

    PERIODS = [ 7, 30, 90 ].freeze
    DEFAULT_DAYS = 30

    def self.for_businesses(businesses, health_result: nil)
      health_by_business_id = Array(health_result&.business_healths).index_by { |row| row.business.id }
      businesses.index_with do |business|
        new(business, health: health_by_business_id[business.id]).call
      end
    end

    def initialize(business, health: nil, today: Date.current)
      @business = business
      @health = health
      @today = today
    end

    def call
      Result.new(
        business:,
        health:,
        last_sync_at: health&.last_sync_at || latest_metric_at || latest_revenue_at,
        warning_count: health&.warning_count.to_i,
        warnings: Array(health&.warnings),
        periods: period_summaries,
        gsc_series: metric_series(:gsc),
        ga4_series: metric_series(:ga4),
        revenue_series: revenue_series,
        action_series: action_series,
        learning_series: learning_series,
        cost_estimates: Aicoo::CostEngine.new(business:).call.estimates,
        settings: settings_summary,
        data_status: data_status
      )
    end

    private

    attr_reader :business, :health, :today

    def period_summaries
      PERIODS.index_with do |days|
        metrics = metrics_for(days)
        impressions = metrics.sum(&:impressions)
        clicks = metrics.sum(&:clicks)
        PeriodSummary.new(
          days:,
          gsc_clicks: clicks,
          gsc_impressions: impressions,
          gsc_ctr: ratio(clicks, impressions),
          ga4_sessions: metrics.sum(&:sessions),
          ga4_pageviews: metrics.sum(&:pageviews),
          revenue_yen: revenue_for(days),
          pending_actions: pending_actions_count,
          warning_count: health&.warning_count.to_i
        )
      end
    end

    def metric_series(kind)
      metric_records_for(DEFAULT_DAYS).map do |record|
        values = if kind == :gsc
          {
            "clicks" => record.clicks,
            "impressions" => record.impressions,
            "ctr" => ratio(record.clicks, record.impressions),
            "average_position" => nil
          }
        else
          {
            "sessions" => record.sessions,
            "pageviews" => record.pageviews,
            "active_users" => nil,
            "conversions" => nil
          }
        end
        ChartPoint.new(date: record.recorded_on, values:)
      end
    end

    def revenue_series
      date_range(DEFAULT_DAYS).map do |date|
        metric = metric_by_date[date]
        ChartPoint.new(
          date:,
          values: {
            "revenue_yen" => revenue_by_date[date].to_i,
            "affiliate_clicks" => metric&.affiliate_clicks.to_i,
            "phone_clicks" => metric&.phone_clicks.to_i,
            "map_clicks" => metric&.map_clicks.to_i
          }
        )
      end
    end

    def action_series
      date_range(DEFAULT_DAYS).map do |date|
        ChartPoint.new(
          date:,
          values: {
            "action_candidates" => action_candidate_counts[date].to_i,
            "executions" => action_execution_counts[date].to_i,
            "results" => action_result_counts[date].to_i
          }
        )
      end
    end

    def learning_series
      date_range(DEFAULT_DAYS).map do |date|
        ChartPoint.new(
          date:,
          values: {
            "decision_logs" => decision_log_counts[date].to_i,
            "playbook_confidence" => business.business_playbook&.confidence_score.to_d,
            "practicality_average" => practicality_average_by_date[date].to_d,
            "evidence_average" => evidence_average_by_date[date].to_d
          }
        )
      end
    end

    def settings_summary
      {
        gsc_site_url: business.gsc_site_url,
        ga4_property_id: analytics_site&.ga4_property_id || ga4_setting&.property_id,
        project_key: business.project_key,
        local_project_path: business.local_project_path,
        repository_name: business.repository_name,
        verification_commands: business.codex_verification_commands
      }
    end

    def data_status
      {
        gsc_connected: health&.gsc&.connected || false,
        ga4_connected: health&.ga4&.connected || false,
        has_gsc_data: metric_records_for(DEFAULT_DAYS).any? { |record| record.clicks.positive? || record.impressions.positive? },
        has_ga4_data: metric_records_for(DEFAULT_DAYS).any? { |record| record.sessions.positive? || record.pageviews.positive? },
        has_revenue_data: revenue_by_date.values.any?(&:positive?),
        has_action_data: action_candidate_counts.values.any?(&:positive?),
        has_learning_data: decision_log_counts.values.any?(&:positive?) || business.business_playbook&.learned? || false
      }
    end

    def metrics_for(days)
      business.business_metric_dailies.where(recorded_on: date_range(days))
    end

    def metric_records_for(days)
      @metric_records_for ||= {}
      @metric_records_for[days] ||= business.business_metric_dailies.where(recorded_on: date_range(days)).order(:recorded_on).to_a
    end

    def metric_by_date
      @metric_by_date ||= metric_records_for(DEFAULT_DAYS).index_by(&:recorded_on)
    end

    def revenue_for(days)
      business.revenue_events.revenue.where(occurred_on: date_range(days)).sum(:amount).to_i
    end

    def revenue_by_date
      @revenue_by_date ||= business.revenue_events.revenue
        .where(occurred_on: date_range(DEFAULT_DAYS))
        .group(:occurred_on)
        .sum(:amount)
    end

    def pending_actions_count
      @pending_actions_count ||= business.action_candidates.where.not(status: ActionCandidate::INACTIVE_STATUSES).count
    end

    def action_candidate_counts
      @action_candidate_counts ||= business.action_candidates
        .where(created_at: time_range(DEFAULT_DAYS))
        .group_by { |record| record.created_at.to_date }
        .transform_values(&:count)
    end

    def action_execution_counts
      @action_execution_counts ||= ActionExecution
        .joins(:action_candidate)
        .where(action_candidates: { business_id: business.id })
        .where(created_at: time_range(DEFAULT_DAYS))
        .group_by { |record| record.created_at.to_date }
        .transform_values(&:count)
    end

    def action_result_counts
      @action_result_counts ||= business.action_results
        .where(created_at: time_range(DEFAULT_DAYS))
        .group_by { |record| record.created_at.to_date }
        .transform_values(&:count)
    end

    def decision_log_counts
      @decision_log_counts ||= OwnerDecisionLog
        .where(business:)
        .where(decided_at: time_range(DEFAULT_DAYS))
        .group_by { |record| record.decided_at.to_date }
        .transform_values(&:count)
    end

    def practicality_average_by_date
      @practicality_average_by_date ||= average_candidate_metadata_by_date do |candidate|
        candidate.practicality_score
      end
    end

    def evidence_average_by_date
      @evidence_average_by_date ||= average_candidate_metadata_by_date do |candidate|
        candidate.metadata.to_h.dig("evidence", "score")
      end
    end

    def average_candidate_metadata_by_date
      business.action_candidates.where(created_at: time_range(DEFAULT_DAYS)).group_by { |candidate| candidate.created_at.to_date }.transform_values do |candidates|
        values = candidates.filter_map { |candidate| yield(candidate)&.to_d }
        values.present? ? values.sum / values.size : 0.to_d
      end
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.find_by(business:)
    end

    def ga4_setting
      @ga4_setting ||= AnalyticsSourceSetting.includes(:aicoo_analytics_site)
        .where(source_type: "ga4")
        .find { |setting| setting.aicoo_analytics_site&.business_id == business.id }
    end

    def latest_metric_at
      business.business_metric_dailies.maximum(:recorded_on)&.in_time_zone
    end

    def latest_revenue_at
      business.revenue_events.maximum(:occurred_on)&.in_time_zone
    end

    def date_range(days)
      (today - (days - 1))..today
    end

    def time_range(days)
      (today - (days - 1)).beginning_of_day..today.end_of_day
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_d.zero?

      numerator.to_d / denominator.to_d
    end
  end
end

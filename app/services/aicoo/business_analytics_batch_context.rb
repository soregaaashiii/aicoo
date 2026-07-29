module Aicoo
  class BusinessAnalyticsBatchContext
    DEFAULT_DAYS = BusinessAnalyticsSummary::DEFAULT_DAYS
    MAX_DAYS = BusinessAnalyticsSummary::PERIODS.max

    def initialize(
      businesses,
      today: Date.current,
      include_details: true,
      metric_records: nil,
      revenue_events: nil
    )
      @businesses = Array(businesses)
      @business_ids = @businesses.filter_map(&:id)
      @today = today
      @include_details = include_details
      @provided_metric_records = metric_records
      @provided_revenue_events = revenue_events
      load_data
    end

    def metrics_for(business_id, days)
      metrics_by_business_id.fetch(business_id, []).select { |row| row.recorded_on.in?(date_range(days)) }
    end

    def latest_metric_at(business_id)
      latest_metric_at_by_business_id[business_id]&.in_time_zone
    end

    def revenue_events_for(business_id, days)
      revenue_events_by_business_id.fetch(business_id, []).select { |row| row.occurred_on.in?(date_range(days)) }
    end

    def expected_value_revenue_events_for(business_id)
      expected_value_revenue_events_by_business_id.fetch(business_id, [])
    end

    def latest_revenue_at(business_id)
      latest_revenue_at_by_business_id[business_id]&.in_time_zone
    end

    def pending_actions_count(business_id)
      pending_action_counts.fetch(business_id, 0)
    end

    def recent_candidates(business_id)
      candidates_by_business_id.fetch(business_id, [])
    end

    def action_candidate_counts(business_id)
      count_by_date(recent_candidates(business_id), &:created_at)
    end

    def action_execution_counts(business_id)
      execution_counts_by_business_id.fetch(business_id, {})
    end

    def action_result_counts(business_id)
      result_counts_by_business_id.fetch(business_id, {})
    end

    def decision_log_counts(business_id)
      decision_counts_by_business_id.fetch(business_id, {})
    end

    def analysis_candidates(business_id)
      analysis_candidates_by_business_id.fetch(business_id, [])
    end

    def business_data_source_setting(business_id, source_key)
      business_data_source_settings[[ business_id, source_key ]]
    end

    def analytics_site(business_id)
      analytics_sites_by_business_id[business_id]
    end

    attr_reader :analytics_source_settings

    private

    attr_reader :business_ids, :today, :include_details, :provided_metric_records, :provided_revenue_events

    def load_data
      if provided_metric_records
        all_metrics = Array(provided_metric_records).select { |row| row.business_id.in?(business_ids) }
        @metrics_by_business_id = all_metrics
          .select { |row| row.recorded_on.in?(date_range(MAX_DAYS)) }
          .group_by(&:business_id)
        @latest_metric_at_by_business_id = all_metrics
          .group_by(&:business_id)
          .transform_values { |rows| rows.filter_map(&:recorded_on).max }
      else
        @metrics_by_business_id = BusinessMetricDaily
          .where(business_id: business_ids, recorded_on: date_range(MAX_DAYS))
          .order(:recorded_on)
          .to_a
          .group_by(&:business_id)
        @latest_metric_at_by_business_id = BusinessMetricDaily
          .where(business_id: business_ids)
          .group(:business_id)
          .maximum(:recorded_on)
      end

      if provided_revenue_events
        all_revenue_events = Array(provided_revenue_events).select { |row| row.business_id.in?(business_ids) }
        recent_revenue_events = all_revenue_events.select { |row| row.occurred_on.in?(date_range(MAX_DAYS)) }
        @revenue_events_by_business_id = recent_revenue_events.select(&:revenue?).group_by(&:business_id)
        @expected_value_revenue_events_by_business_id = recent_revenue_events.group_by(&:business_id)
        @latest_revenue_at_by_business_id = all_revenue_events
          .group_by(&:business_id)
          .transform_values { |rows| rows.filter_map(&:occurred_on).max }
      else
        @revenue_events_by_business_id = RevenueEvent.revenue
          .where(business_id: business_ids, occurred_on: date_range(MAX_DAYS))
          .to_a
          .group_by(&:business_id)
        @expected_value_revenue_events_by_business_id = RevenueEvent
          .where(business_id: business_ids, occurred_on: date_range(MAX_DAYS))
          .to_a
          .group_by(&:business_id)
        @latest_revenue_at_by_business_id = RevenueEvent
          .where(business_id: business_ids)
          .group(:business_id)
          .maximum(:occurred_on)
      end
      @pending_action_counts = ActionCandidate
        .where(business_id: business_ids)
        .where.not(status: ActionCandidate::INACTIVE_STATUSES)
        .group(:business_id)
        .count
      if include_details
        load_detail_data
      else
        @candidates_by_business_id = {}
        @execution_counts_by_business_id = {}
        @result_counts_by_business_id = {}
        @decision_counts_by_business_id = {}
        @analysis_candidates_by_business_id = {}
        @business_data_source_settings = {}
        @analytics_sites_by_business_id = {}
        @analytics_source_settings = []
      end
    end

    def load_detail_data
      @candidates_by_business_id = ActionCandidate
        .where(business_id: business_ids, created_at: time_range(DEFAULT_DAYS))
        .select(:id, :business_id, :created_at, :practicality_score, :metadata)
        .to_a
        .group_by(&:business_id)
      @execution_counts_by_business_id = count_pairs_by_business_and_date(
        ActionExecution
          .joins(:action_candidate)
          .where(action_candidates: { business_id: business_ids })
          .where(created_at: time_range(DEFAULT_DAYS))
          .pluck("action_candidates.business_id", "action_executions.created_at")
      )
      @result_counts_by_business_id = count_pairs_by_business_and_date(
        ActionResult
          .where(business_id: business_ids, created_at: time_range(DEFAULT_DAYS))
          .pluck(:business_id, :created_at)
      )
      @decision_counts_by_business_id = count_pairs_by_business_and_date(
        OwnerDecisionLog
          .where(business_id: business_ids, decided_at: time_range(DEFAULT_DAYS))
          .pluck(:business_id, :decided_at)
      )
      @analysis_candidates_by_business_id = AnalysisCandidate
        .where(business_id: business_ids, due_on: today)
        .ordered
        .to_a
        .group_by(&:business_id)
        .transform_values { |rows| rows.first(8) }
      @business_data_source_settings = BusinessDataSourceSetting
        .where(business_id: business_ids, source_key: %w[gsc ga4])
        .index_by { |row| [ row.business_id, row.source_key ] }
      @analytics_sites_by_business_id = AicooAnalyticsSite
        .where(business_id: business_ids)
        .order(created_at: :desc)
        .to_a
        .group_by(&:business_id)
        .transform_values(&:first)
      @analytics_source_settings = AnalyticsSourceSetting.includes(:aicoo_analytics_site).to_a
    end

    def count_pairs_by_business_and_date(rows)
      rows.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |(business_id, occurred_at), result|
        result[business_id][occurred_at.to_date] += 1
      end
    end

    def count_by_date(rows)
      rows.group_by { |row| yield(row).to_date }.transform_values(&:size)
    end

    def date_range(days)
      (today - (days - 1))..today
    end

    def time_range(days)
      (today - (days - 1)).beginning_of_day..today.end_of_day
    end

    attr_reader :metrics_by_business_id,
                :latest_metric_at_by_business_id,
                :revenue_events_by_business_id,
                :expected_value_revenue_events_by_business_id,
                :latest_revenue_at_by_business_id,
                :pending_action_counts,
                :candidates_by_business_id,
                :execution_counts_by_business_id,
                :result_counts_by_business_id,
                :decision_counts_by_business_id,
                :analysis_candidates_by_business_id,
                :business_data_source_settings,
                :analytics_sites_by_business_id
  end
end

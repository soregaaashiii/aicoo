module Aicoo
  class ActivityEvaluationBuilder
    WINDOWS = [ 7, 14, 30 ].freeze
    METRICS = %i[
      impressions
      clicks
      average_position
      sessions
      pageviews
      users
      engagement_rate
      phone_clicks
      map_clicks
      affiliate_clicks
      conversions
    ].freeze

    Result = Struct.new(:created_count, :evaluated_count, :skipped_count, :pending_count, keyword_init: true)

    def call(business: nil)
      result = Result.new(created_count: 0, evaluated_count: 0, skipped_count: 0, pending_count: 0)
      scope = BusinessActivityLog.evaluation_due
      scope = scope.where(business:) if business
      scope.find_each do |activity_log|
        evaluate_log(activity_log, result)
      end
      result
    end

    private

    def evaluate_log(activity_log, result)
      activity_log.evaluation_evaluating!
      WINDOWS.each do |window|
        evaluate_window(activity_log, window, result)
      end
      refresh_activity_status(activity_log)
    rescue StandardError => e
      activity_log.update!(evaluation_status: "pending", metadata: activity_log.metadata.merge("evaluation_error" => "#{e.class}: #{e.message}"))
      raise
    end

    def evaluate_window(activity_log, window, result)
      if activity_log.occurred_at + window.days > Time.current
        result.pending_count += 1
        return
      end

      evaluation = ActivityEvaluation.find_or_initialize_by(business_activity_log: activity_log, evaluation_window_days: window)
      result.created_count += 1 if evaluation.new_record?
      snapshots = snapshots_for(activity_log, window)
      if snapshots[:baseline].blank? || snapshots[:result].blank?
        evaluation.assign_attributes(
          business: activity_log.business,
          status: "skipped",
          skip_reason: "insufficient_metric_data",
          evaluated_at: Time.current,
          baseline_snapshot: snapshots[:baseline] || {},
          result_snapshot: snapshots[:result] || {}
        )
        evaluation.save!
        result.skipped_count += 1
        return
      end

      evaluation.assign_attributes(
        business: activity_log.business,
        status: "evaluated",
        baseline_snapshot: snapshots[:baseline],
        result_snapshot: snapshots[:result],
        metric_deltas: delta_for(snapshots[:baseline], snapshots[:result]),
        evaluated_at: Time.current,
        skip_reason: nil
      )
      evaluation.save!
      result.evaluated_count += 1
    end

    def snapshots_for(activity_log, window)
      occurred_on = activity_log.occurred_at.to_date
      baseline_range = (occurred_on - 7.days)...occurred_on
      result_range = (occurred_on + 1.day)..(occurred_on + window.days)
      {
        baseline: aggregate(activity_log.business, baseline_range),
        result: aggregate(activity_log.business, result_range)
      }
    end

    def aggregate(business, range)
      metrics = business.business_metric_dailies.where(recorded_on: range)
      return {} if metrics.empty?

      metric_values = METRICS.index_with do |metric|
        if %i[average_position engagement_rate].include?(metric)
          metrics.average(metric).to_f.round(4)
        else
          metrics.sum(metric).to_f
        end
      end
      metric_values.merge(
        revenue_yen: business.revenue_events.revenue.where(occurred_on: range).sum(:amount).to_f
      )
    end

    def delta_for(baseline, result)
      result.index_with do |metric, value|
        before = baseline[metric].to_f
        after = value.to_f
        {
          before:,
          after:,
          delta: after - before,
          change_rate: before.zero? ? nil : ((after - before) / before).round(4)
        }
      end
    end

    def refresh_activity_status(activity_log)
      evaluations = activity_log.activity_evaluations
      if evaluations.evaluated.exists?
        activity_log.evaluation_evaluated!
      elsif evaluations.skipped.count == WINDOWS.size
        activity_log.evaluation_skipped!
      else
        activity_log.evaluation_pending!
      end
    end
  end
end

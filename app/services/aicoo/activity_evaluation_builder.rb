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

    Result = Struct.new(
      :created_count,
      :evaluated_count,
      :skipped_count,
      :pending_count,
      :failed_count,
      :action_results_generated_count,
      keyword_init: true
    )

    def call(business: nil)
      result = Result.new(
        created_count: 0,
        evaluated_count: 0,
        skipped_count: 0,
        pending_count: 0,
        failed_count: 0,
        action_results_generated_count: 0
      )
      scope = evaluation_scope
      scope = scope.where(business:) if business
      scope.find_each do |activity_log|
        begin
          evaluate_log(activity_log, result)
        rescue StandardError => e
          result.failed_count += 1
          Rails.logger.error(
            "[ActivityEvaluationBuilder] failed activity_log_id=#{activity_log.id} " \
            "activity_type=#{activity_log.activity_type} error=#{e.class}: #{e.message}"
          )
        end
      end
      result
    end

    private

    def evaluation_scope
      pending_log_ids = ActivityEvaluation.pending.select(:business_activity_log_id)
      BusinessActivityLog
        .where(evaluation_status: %w[pending evaluating])
        .or(BusinessActivityLog.where(id: pending_log_ids))
        .distinct
    end

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
      evaluation = ActivityEvaluation.find_or_initialize_by(business_activity_log: activity_log, evaluation_window_days: window)
      return if evaluation.persisted? && !evaluation.pending?

      if activity_log.occurred_at + window.days > Time.current
        assign_pending_evaluation(evaluation, activity_log, window)
        result.created_count += 1 if evaluation.new_record?
        evaluation.save!
        result.pending_count += 1
        return
      end

      result.created_count += 1 if evaluation.new_record?
      snapshots = snapshots_for(activity_log, window)
      if snapshots[:baseline].blank? || snapshots[:result].blank?
        evaluation.assign_attributes(
          business: activity_log.business,
          status: "skipped",
          skip_reason: "insufficient_metric_data",
          evaluated_at: Time.current,
          baseline_snapshot: snapshots[:baseline] || {},
          result_snapshot: snapshots[:result] || {},
          metadata: evaluation.metadata.to_h.merge(
            "activity_evaluation_builder" => builder_metadata(
              state: "skipped",
              reason: "insufficient_metric_data",
              due_at: activity_log.occurred_at + window.days
            )
          )
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
        skip_reason: nil,
        metadata: evaluation.metadata.to_h.merge(
          "activity_evaluation_builder" => builder_metadata(
            state: "evaluated",
            due_at: activity_log.occurred_at + window.days
          )
        )
      )
      evaluation.save!
      result.evaluated_count += 1
      bridge_result = Aicoo::ActivityActionResultBridge.call(evaluation)
      result.action_results_generated_count += 1 if bridge_result.status == "generated"
    end

    def assign_pending_evaluation(evaluation, activity_log, window)
      evaluation.assign_attributes(
        business: activity_log.business,
        status: "pending",
        evaluated_at: nil,
        skip_reason: nil,
        metadata: evaluation.metadata.to_h.merge(
          "activity_evaluation_builder" => builder_metadata(
            state: "pending",
            reason: "evaluation_window_not_due",
            due_at: activity_log.occurred_at + window.days
          )
        )
      )
    end

    def builder_metadata(state:, due_at:, reason: nil)
      {
        "state" => state,
        "reason" => reason,
        "due_at" => due_at.iso8601,
        "last_checked_at" => Time.current.iso8601
      }.compact
    end

    def snapshots_for(activity_log, window)
      occurred_on = activity_log.occurred_at.to_date
      baseline_range = (occurred_on - 7.days)...occurred_on
      result_range = (occurred_on + 1.day)..(occurred_on + window.days)
      {
        baseline: aggregate(activity_log.business, baseline_range).merge(resource_snapshot(activity_log, baseline_range)),
        result: aggregate(activity_log.business, result_range).merge(resource_snapshot(activity_log, result_range))
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

    def resource_snapshot(activity_log, range)
      return {} unless suelog_shop_activity?(activity_log)

      suelog_shop_click_snapshot(activity_log, range)
    rescue StandardError => e
      {
        "resource_metric_error" => "#{e.class}: #{e.message}".truncate(180),
        "resource_metric_source" => "suelog_shop_clicks"
      }
    end

    def suelog_shop_activity?(activity_log)
      activity_log.source_app.to_s == "suelog" &&
        activity_log.resource_type.to_s == "Shop" &&
        activity_log.resource_id.present?
    end

    def suelog_shop_click_snapshot(activity_log, range)
      return {} unless defined?(::Suelog::ShopClick)

      scope = ::Suelog::ShopClick.where(shop_id: activity_log.resource_id.to_s)
      scope = scope.where(created_at: range)
      snapshot = {
        "resource_metric_source" => "suelog_shop_clicks",
        "resource_type" => activity_log.resource_type,
        "resource_id" => activity_log.resource_id,
        "shop_clicks" => scope.count.to_f
      }
      click_type_column = suelog_shop_click_type_column
      if click_type_column
        scope.group(click_type_column).count.each do |type, count|
          key = type.to_s.presence || "unknown"
          snapshot["shop_clicks_#{key.parameterize(separator: '_')}"] = count.to_f
        end
      end
      snapshot
    end

    def suelog_shop_click_type_column
      @suelog_shop_click_type_column ||= begin
        columns = ::Suelog::ShopClick.column_names
        %w[click_type kind event_type action].find { |column| columns.include?(column) }
      rescue StandardError
        nil
      end
    end

    def delta_for(baseline, result)
      result.index_with do |metric, value|
        next non_numeric_delta(baseline[metric], value) unless numeric_like?(value) && numeric_like?(baseline[metric])

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

    def numeric_like?(value)
      value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
    end

    def non_numeric_delta(before, after)
      {
        before:,
        after:,
        delta: nil,
        change_rate: nil
      }
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
      clear_evaluation_error(activity_log)
    end

    def clear_evaluation_error(activity_log)
      metadata = activity_log.metadata.to_h
      return unless metadata.key?("evaluation_error")

      activity_log.update!(metadata: metadata.except("evaluation_error"))
    end
  end
end

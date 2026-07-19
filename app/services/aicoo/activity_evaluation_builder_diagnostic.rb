module Aicoo
  class ActivityEvaluationBuilderDiagnostic
    Row = Data.define(
      :event_id,
      :activity_type,
      :business_id,
      :received_at,
      :eligible,
      :eligibility_reason,
      :evaluation_status,
      :evaluation_generated,
      :evaluation_windows,
      :missing_windows,
      :due_windows,
      :pending_windows,
      :excluded_reason,
      :missing_reason,
      :result
    )
    Summary = Data.define(
      :activity_count,
      :eligible_count,
      :excluded_count,
      :evaluation_generated_count,
      :generation_failed_count,
      :evaluation_record_count,
      :reason_counts
    )
    Result = Data.define(:rows, :summary)

    def initialize(business_id: nil, limit: nil)
      @business_id = business_id.presence
      @limit = limit.to_i if limit.to_i.positive?
    end

    def call
      rows = scoped_logs.map { |log| row_for(log) }
      Result.new(rows:, summary: summary_for(rows))
    end

    private

    attr_reader :business_id, :limit

    def scoped_logs
      scope = BusinessActivityLog.includes(:activity_evaluations).order(:id)
      scope = scope.where(business_id:) if business_id
      scope = scope.limit(limit) if limit
      scope
    end

    def row_for(log)
      evaluations = log.activity_evaluations.index_by(&:evaluation_window_days)
      existing_windows = evaluations.keys.sort
      missing_windows = ActivityEvaluationBuilder::WINDOWS - existing_windows
      due_windows = ActivityEvaluationBuilder::WINDOWS.select { |window| due?(log, window) }
      pending_windows = evaluations.values.select(&:pending?).map(&:evaluation_window_days).sort
      eligible = eligible?(log)
      missing_reason = missing_reason_for(log, eligible, evaluations, missing_windows)

      Row.new(
        event_id: log.id,
        activity_type: log.activity_type,
        business_id: log.business_id,
        received_at: log.detected_at,
        eligible:,
        eligibility_reason: eligible ? "valid_business_activity_log" : "invalid_business_activity_log",
        evaluation_status: log.evaluation_status,
        evaluation_generated: evaluations.any?,
        evaluation_windows: existing_windows,
        missing_windows:,
        due_windows:,
        pending_windows:,
        excluded_reason: eligible ? nil : "required_activity_fields_missing",
        missing_reason:,
        result: result_for(eligible, evaluations, missing_reason)
      )
    end

    def eligible?(log)
      log.business_id.present? && log.activity_type.present? && log.occurred_at.present?
    end

    def due?(log, window)
      log.occurred_at + window.days <= Time.current
    end

    def missing_reason_for(log, eligible, evaluations, missing_windows)
      return "evaluation_target_excluded" unless eligible
      return log.metadata.to_h["evaluation_error"] if log.metadata.to_h["evaluation_error"].present?
      return "activity_evaluation_builder_not_run" if evaluations.empty?
      return "evaluation_windows_missing" if missing_windows.any?

      nil
    end

    def result_for(eligible, evaluations, missing_reason)
      return "excluded" unless eligible
      return "FAIL" if missing_reason.present?
      return "PASS" if evaluations.any?

      "WARNING"
    end

    def summary_for(rows)
      Summary.new(
        activity_count: rows.size,
        eligible_count: rows.count(&:eligible),
        excluded_count: rows.count { |row| !row.eligible },
        evaluation_generated_count: rows.count(&:evaluation_generated),
        generation_failed_count: rows.count { |row| row.eligible && !row.evaluation_generated },
        evaluation_record_count: rows.sum { |row| row.evaluation_windows.size },
        reason_counts: rows.filter_map(&:missing_reason).tally
      )
    end
  end
end

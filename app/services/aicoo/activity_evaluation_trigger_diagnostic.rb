module Aicoo
  class ActivityEvaluationTriggerDiagnostic
    Row = Data.define(
      :event_id,
      :business_id,
      :activity_type,
      :builder_should_run,
      :builder_trigger_found,
      :builder_invoked,
      :invoked_by,
      :builder_completed,
      :builder_exception,
      :skip_reason
    )
    Summary = Data.define(
      :activity_count,
      :builder_should_run_count,
      :builder_invoked_count,
      :builder_not_invoked_count,
      :builder_completed_count,
      :builder_failed_count,
      :reason_counts
    )
    Result = Data.define(:rows, :summary)

    def initialize(business_id: nil, limit: nil)
      @business_id = business_id.presence
      @limit = limit.to_i if limit.to_i.positive?
    end

    def call
      rows = scoped_logs.map { |activity_log| row_for(activity_log) }
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

    def row_for(activity_log)
      trigger = activity_log.metadata.to_h["activity_evaluation_trigger"].to_h
      evaluations = activity_log.activity_evaluations
      legacy_invocation = evaluations.any?
      invoked = trigger["builder_invoked"] == true || legacy_invocation
      completed = trigger.key?("builder_completed") ? trigger["builder_completed"] == true : legacy_invocation
      exception = trigger["builder_exception"].presence || activity_log.metadata.to_h["evaluation_error"].presence
      skip_reason = skip_reason_for(activity_log, invoked, completed, exception)

      Row.new(
        event_id: activity_log.id,
        business_id: activity_log.business_id,
        activity_type: activity_log.activity_type,
        builder_should_run: eligible?(activity_log),
        builder_trigger_found: invoked,
        builder_invoked: invoked,
        invoked_by: trigger["invoked_by"].presence || (legacy_invocation ? "legacy_builder" : nil),
        builder_completed: completed,
        builder_exception: exception,
        skip_reason:
      )
    end

    def eligible?(activity_log)
      activity_log.business_id.present? && activity_log.activity_type.present? && activity_log.occurred_at.present?
    end

    def skip_reason_for(activity_log, invoked, completed, exception)
      return "required_activity_fields_missing" unless eligible?(activity_log)
      return "activity_evaluation_builder_not_invoked" unless invoked
      return "builder_exception" if exception.present?
      return "activity_evaluation_not_generated" unless completed

      nil
    end

    def summary_for(rows)
      should_run_rows = rows.select(&:builder_should_run)
      Summary.new(
        activity_count: rows.size,
        builder_should_run_count: should_run_rows.size,
        builder_invoked_count: should_run_rows.count(&:builder_invoked),
        builder_not_invoked_count: should_run_rows.count { |row| !row.builder_invoked },
        builder_completed_count: should_run_rows.count(&:builder_completed),
        builder_failed_count: should_run_rows.count { |row| row.builder_invoked && !row.builder_completed },
        reason_counts: rows.filter_map(&:skip_reason).tally
      )
    end
  end
end

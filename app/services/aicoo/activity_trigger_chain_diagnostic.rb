module Aicoo
  class ActivityTriggerChainDiagnostic
    Row = Data.define(
      :event_id,
      :activity_type,
      :business_id,
      :record_created,
      :after_create_called,
      :after_commit_called,
      :after_commit_skipped,
      :trigger_registered,
      :trigger_called,
      :trigger_completed,
      :builder_called,
      :builder_completed,
      :return_point,
      :exception,
      :skip_reason
    )
    Summary = Data.define(
      :record_count,
      :after_commit_count,
      :trigger_registered_count,
      :trigger_called_count,
      :builder_called_count,
      :builder_completed_count,
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
      metadata = activity_log.metadata.to_h
      chain = metadata["activity_evaluation_trigger_chain"].to_h
      trigger = metadata["activity_evaluation_trigger"].to_h
      legacy_builder = activity_log.activity_evaluations.any? && trigger.empty? && chain.empty?
      trigger_called = chain["trigger_called"] == true || trigger["builder_invoked"] == true || legacy_builder
      builder_called = chain["builder_called"] == true || trigger["builder_invoked"] == true || legacy_builder
      builder_completed = chain["builder_completed"] == true || trigger["builder_completed"] == true || legacy_builder
      exception = chain["exception"].presence || trigger["builder_exception"].presence || metadata["evaluation_error"].presence
      after_commit_called = chain["after_commit_called"] == true

      Row.new(
        event_id: activity_log.id,
        activity_type: activity_log.activity_type,
        business_id: activity_log.business_id,
        record_created: true,
        after_create_called: chain["after_create_called"] == true,
        after_commit_called:,
        after_commit_skipped: chain["after_commit_skipped"] == true || !after_commit_called,
        trigger_registered: chain["trigger_registered"] == true || trigger_called,
        trigger_called:,
        trigger_completed: chain["trigger_completed"] == true || trigger["builder_completed"] == true || legacy_builder,
        builder_called:,
        builder_completed:,
        return_point: return_point_for(chain, trigger, legacy_builder),
        exception:,
        skip_reason: skip_reason_for(chain, trigger_called, builder_called, builder_completed, exception, legacy_builder)
      )
    end

    def return_point_for(chain, trigger, legacy_builder)
      return chain["return_point"] if chain["return_point"].present?
      return "legacy_builder_completed" if legacy_builder
      return "trigger_completed" if trigger["builder_completed"] == true
      return "trigger_called" if trigger["builder_invoked"] == true

      "record_committed_without_trigger"
    end

    def skip_reason_for(chain, trigger_called, builder_called, builder_completed, exception, legacy_builder)
      return nil if builder_completed
      return chain["skip_reason"] if chain["skip_reason"].present?
      return "trigger_exception" if exception.present? && trigger_called
      return "builder_exception" if exception.present? && builder_called
      return "builder_incomplete" if builder_called
      return "legacy_builder_incomplete" if legacy_builder
      return "activity_evaluation_trigger_not_called" unless trigger_called

      "activity_evaluation_builder_not_called"
    end

    def summary_for(rows)
      Summary.new(
        record_count: rows.size,
        after_commit_count: rows.count(&:after_commit_called),
        trigger_registered_count: rows.count(&:trigger_registered),
        trigger_called_count: rows.count(&:trigger_called),
        builder_called_count: rows.count(&:builder_called),
        builder_completed_count: rows.count(&:builder_completed),
        reason_counts: rows.filter_map(&:skip_reason).tally
      )
    end
  end
end

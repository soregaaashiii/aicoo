module Aicoo
  class BusinessActivityLogCreationDiagnostic
    Row = Data.define(
      :event_id,
      :created_by_method,
      :created_by_file,
      :created_by_line,
      :persistence_method,
      :active_record_callbacks_enabled,
      :after_create_called,
      :after_commit_called,
      :callback_skipped_reason,
      :trigger_registered,
      :trigger_called,
      :builder_called
    )
    Summary = Data.define(
      :record_count,
      :after_create_called_count,
      :after_commit_count,
      :callback_executed_count,
      :callback_not_executed_count,
      :trigger_registered_count,
      :trigger_called_count,
      :builder_called_count,
      :creation_path_counts,
      :callback_skip_reason_counts
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
      creation = metadata["business_activity_log_creation"].to_h
      chain = metadata["activity_evaluation_trigger_chain"].to_h
      trigger = metadata["activity_evaluation_trigger"].to_h
      legacy_builder = activity_log.activity_evaluations.any? && trigger.empty? && chain.empty?
      after_create_called = chain["after_create_called"] == true
      after_commit_called = chain["after_commit_called"] == true
      trigger_called = chain["trigger_called"] == true || trigger["builder_invoked"] == true || legacy_builder
      builder_called = chain["builder_called"] == true || trigger["builder_invoked"] == true || legacy_builder

      Row.new(
        event_id: activity_log.id,
        created_by_method: creation["created_by_method"].presence || "legacy_uninstrumented",
        created_by_file: creation["created_by_file"].presence,
        created_by_line: creation["created_by_line"],
        persistence_method: creation["persistence_method"].presence || "unknown",
        active_record_callbacks_enabled: creation.key?("active_record_callbacks_enabled") ? creation["active_record_callbacks_enabled"] == true : nil,
        after_create_called:,
        after_commit_called:,
        callback_skipped_reason: callback_skipped_reason(creation, after_create_called, after_commit_called),
        trigger_registered: chain["trigger_registered"] == true || trigger_called,
        trigger_called:,
        builder_called:
      )
    end

    def callback_skipped_reason(creation, after_create_called, after_commit_called)
      return nil if after_create_called && after_commit_called
      return "creation_provenance_missing" if creation.empty?
      return "active_record_callbacks_disabled" if creation["active_record_callbacks_enabled"] == false
      return "after_create_not_observed" unless after_create_called

      "after_commit_not_observed"
    end

    def summary_for(rows)
      Summary.new(
        record_count: rows.size,
        after_create_called_count: rows.count(&:after_create_called),
        after_commit_count: rows.count(&:after_commit_called),
        callback_executed_count: rows.count { |row| row.after_create_called && row.after_commit_called },
        callback_not_executed_count: rows.count { |row| !row.after_create_called || !row.after_commit_called },
        trigger_registered_count: rows.count(&:trigger_registered),
        trigger_called_count: rows.count(&:trigger_called),
        builder_called_count: rows.count(&:builder_called),
        creation_path_counts: rows.map { |row| creation_path_for(row) }.tally,
        callback_skip_reason_counts: rows.filter_map(&:callback_skipped_reason).tally
      )
    end

    def creation_path_for(row)
      [ row.persistence_method, row.created_by_file, row.created_by_method ].compact.join(":")
    end
  end
end

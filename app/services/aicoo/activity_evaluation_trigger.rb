module Aicoo
  class ActivityEvaluationTrigger
    Result = Data.define(
      :builder_should_run_count,
      :builder_invoked_count,
      :builder_completed_count,
      :builder_failed_count,
      :builder_result,
      :exception
    )

    def self.call(business: nil, invoked_by:, trigger_event_id: nil)
      new(business:, invoked_by:, trigger_event_id:).call
    end

    def initialize(business:, invoked_by:, trigger_event_id:)
      @business = business
      @invoked_by = invoked_by.to_s
      @trigger_event_id = trigger_event_id
    end

    def call
      activity_logs = target_activity_logs.to_a
      mark_started(activity_logs)
      builder_result = ActivityEvaluationBuilder.new.call(business:)
      completed_count, failed_count = mark_finished(activity_logs)

      Result.new(
        builder_should_run_count: activity_logs.size,
        builder_invoked_count: activity_logs.size,
        builder_completed_count: completed_count,
        builder_failed_count: failed_count,
        builder_result:,
        exception: nil
      )
    rescue StandardError => e
      mark_failed(activity_logs || [], e)
      Rails.logger.error(
        "[ActivityEvaluationTrigger] failed invoked_by=#{invoked_by} " \
        "trigger_event_id=#{trigger_event_id || '-'} error=#{e.class}: #{e.message}"
      )
      Result.new(
        builder_should_run_count: activity_logs&.size.to_i,
        builder_invoked_count: activity_logs&.size.to_i,
        builder_completed_count: 0,
        builder_failed_count: activity_logs&.size.to_i,
        builder_result: nil,
        exception: "#{e.class}: #{e.message}"
      )
    end

    private

    attr_reader :business, :invoked_by, :trigger_event_id

    def target_activity_logs
      scope = BusinessActivityLog.includes(:activity_evaluations).order(:id)
      scope = scope.where(business:) if business
      scope.select do |activity_log|
        activity_log.activity_evaluations.empty? || activity_log.activity_evaluations.any?(&:pending?)
      end
    end

    def mark_started(activity_logs)
      activity_logs.each do |activity_log|
        trigger_metadata = activity_log.metadata.to_h["activity_evaluation_trigger"].to_h
        chain_metadata = activity_log.metadata.to_h["activity_evaluation_trigger_chain"].to_h
        write_trigger_metadata(
          activity_log,
          trigger_metadata.merge(
            "builder_should_run" => true,
            "builder_invoked" => true,
            "builder_completed" => false,
            "invoked_by" => invoked_by,
            "trigger_event_id" => trigger_event_id,
            "invocation_count" => trigger_metadata["invocation_count"].to_i + 1,
            "invoked_at" => Time.current.iso8601,
            "builder_exception" => nil,
            "skip_reason" => nil
          ),
          chain_metadata: chain_metadata.merge(
            "record_created" => true,
            "after_commit_called" => true,
            "after_commit_skipped" => false,
            "trigger_registered" => true,
            "trigger_called" => true,
            "trigger_completed" => false,
            "builder_called" => true,
            "builder_completed" => false,
            "invoked_by" => invoked_by,
            "called_at" => Time.current.iso8601,
            "return_point" => "builder_called",
            "exception" => nil,
            "skip_reason" => nil
          )
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[ActivityEvaluationTrigger] start metadata save failed " \
          "activity_log_id=#{activity_log.id} error=#{e.class}: #{e.message}"
        )
      end
    end

    def mark_finished(activity_logs)
      completed_count = 0
      failed_count = 0
      activity_logs.each do |activity_log|
        activity_log.reload
        completed = activity_log.activity_evaluations.exists?
        exception = activity_log.metadata.to_h["evaluation_error"].presence
        completed_count += 1 if completed
        failed_count += 1 unless completed
        trigger_metadata = activity_log.metadata.to_h["activity_evaluation_trigger"].to_h
        chain_metadata = activity_log.metadata.to_h["activity_evaluation_trigger_chain"].to_h
        write_trigger_metadata(
          activity_log,
          trigger_metadata.merge(
            "builder_completed" => completed,
            "builder_exception" => exception,
            "completed_at" => Time.current.iso8601,
            "evaluation_count" => activity_log.activity_evaluations.count,
            "skip_reason" => completed ? nil : exception.presence || "activity_evaluation_not_generated"
          ),
          chain_metadata: chain_metadata.merge(
            "trigger_completed" => true,
            "builder_called" => true,
            "builder_completed" => completed,
            "completed_at" => Time.current.iso8601,
            "return_point" => completed ? "completed" : "builder_incomplete",
            "exception" => exception,
            "skip_reason" => completed ? nil : exception.presence || "activity_evaluation_not_generated"
          )
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[ActivityEvaluationTrigger] finish metadata save failed " \
          "activity_log_id=#{activity_log.id} error=#{e.class}: #{e.message}"
        )
      end
      [ completed_count, failed_count ]
    end

    def mark_failed(activity_logs, error)
      activity_logs.each do |activity_log|
        activity_log.reload
        trigger_metadata = activity_log.metadata.to_h["activity_evaluation_trigger"].to_h
        chain_metadata = activity_log.metadata.to_h["activity_evaluation_trigger_chain"].to_h
        write_trigger_metadata(
          activity_log,
          trigger_metadata.merge(
            "builder_completed" => false,
            "builder_exception" => "#{error.class}: #{error.message}",
            "completed_at" => Time.current.iso8601,
            "skip_reason" => "builder_exception"
          ),
          chain_metadata: chain_metadata.merge(
            "trigger_completed" => false,
            "builder_called" => true,
            "builder_completed" => false,
            "completed_at" => Time.current.iso8601,
            "return_point" => "builder_exception",
            "exception" => "#{error.class}: #{error.message}",
            "skip_reason" => "builder_exception"
          )
        )
      rescue StandardError => metadata_error
        Rails.logger.warn(
          "[ActivityEvaluationTrigger] failure metadata save failed " \
          "activity_log_id=#{activity_log.id} error=#{metadata_error.class}: #{metadata_error.message}"
        )
      end
    end

    def write_trigger_metadata(activity_log, trigger_metadata, chain_metadata: nil)
      metadata = activity_log.metadata.to_h.merge("activity_evaluation_trigger" => trigger_metadata)
      metadata["activity_evaluation_trigger_chain"] = chain_metadata if chain_metadata
      activity_log.update_columns(
        metadata:,
        updated_at: Time.current
      )
    end
  end
end

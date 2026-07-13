module Aicoo
  class CodexActionQueueSummary
    Result = Data.define(
      :queued_count,
      :ready_count,
      :sent_count,
      :running_count,
      :completed_count,
      :failed_count,
      :paused,
      :pause_reason,
      :last_started_at,
      :last_failure_reason,
      :next_task,
      :consecutive_failures
    )

    def call
      setting = AicooAutoRevisionSetting.current
      Result.new(
        queued_count: AutoRevisionTask.where(status: "queued").count,
        ready_count: AutoRevisionTask.where(status: "ready_for_codex").count,
        sent_count: AutoRevisionTask.where(status: "sent_to_codex").count,
        running_count: AutoRevisionTask.where(status: "running").count,
        completed_count: AutoRevisionTask.where(status: %w[completed succeeded partial_succeeded]).count,
        failed_count: AutoRevisionTask.where(status: "failed").count,
        paused: setting.codex_queue_paused?,
        pause_reason: setting.codex_queue_pause_reason,
        last_started_at: AutoRevisionTask.where.not(sent_to_codex_at: nil).maximum(:sent_to_codex_at),
        last_failure_reason: AutoRevisionTask.where(status: "failed").recent.first&.error_message,
        next_task: next_task,
        consecutive_failures: consecutive_failures
      )
    end

    private

    def next_task
      AutoRevisionTask
        .joins(:action_candidate)
        .includes(:business, :action_candidate)
        .where(status: Aicoo::CodexActionQueueProcessor::WAITING_STATUSES, risk_level: "low")
        .order(Aicoo::CodexActionQueueProcessor::ORDER_SQL)
        .limit(50)
        .detect { |task| !blocked_by_prerequisite?(task.action_candidate) }
    end

    def blocked_by_prerequisite?(candidate)
      metadata = candidate.metadata.to_h
      return true if metadata["blocked"] && metadata["prerequisite_action_candidate_id"].blank?

      prerequisite_id = metadata["prerequisite_action_candidate_id"]
      return false if prerequisite_id.blank?

      prerequisite = ActionCandidate.find_by(id: prerequisite_id)
      prerequisite.blank? || !prerequisite.executed?
    end

    def consecutive_failures
      count = 0
      AutoRevisionTask.order(updated_at: :desc, id: :desc).limit(20).pluck(:status).each do |status|
        break unless status == "failed"

        count += 1
      end
      count
    end
  end
end

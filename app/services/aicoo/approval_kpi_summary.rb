module Aicoo
  class ApprovalKpiSummary
    Summary = Data.define(
      :pending_approval_count,
      :reasonless_approval_count,
      :auto_execution_rate,
      :owner_decision_count,
      :ideal_reasonless_approval_count,
      :ideal_pending_approval_range,
      :ideal_auto_execution_rate
    )

    AUTO_ACTIONS = %w[
      sent_to_codex
      auto_released_no_owner_approval_reason
      github_issue_failed
      precheck_failed
      non_code_revision
    ].freeze
    OWNER_ACTIONS = %w[
      approval_required
      approval_required_due_to_risk
      manual_proposal
    ].freeze

    def call
      Summary.new(
        pending_approval_count: pending_approval_count,
        reasonless_approval_count: reasonless_approval_count,
        auto_execution_rate: auto_execution_rate,
        owner_decision_count: owner_decision_count,
        ideal_reasonless_approval_count: 0,
        ideal_pending_approval_range: "0〜3件",
        ideal_auto_execution_rate: "95%以上"
      )
    end

    private

    def pending_approval_count
      AutoRevisionTask.where(status: %w[draft waiting_approval approved]).count(&:owner_approval_required?) +
        ActionPredictionCalibration.where(approval_status: "pending").count
    end

    def reasonless_approval_count
      AutoRevisionTask.where(status: %w[draft waiting_approval approved]).count do |task|
        !task.owner_approval_required?
      end
    end

    def owner_decision_count
      pending_approval_count
    end

    def auto_execution_rate
      logs = AutoRevisionRunLog.where(created_at: 30.days.ago..Time.current)
      auto_count = logs.count { |log| AUTO_ACTIONS.include?(log.metadata.to_h["action"]) || log.status.in?(%w[sent_to_codex ready_for_codex]) }
      owner_count = logs.count { |log| OWNER_ACTIONS.include?(log.metadata.to_h["action"]) || log.metadata.to_h["owner_approval_required"] == true }
      total = auto_count + owner_count
      return 100 if total.zero?

      ((auto_count.to_d / total) * 100).round(1)
    end
  end
end

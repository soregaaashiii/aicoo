module Aicoo
  class AutoRevisionExecutionSummary
    Summary = Data.define(
      :waiting_approval_count,
      :queued_count,
      :running_count,
      :failed_count,
      :completed_today_count,
      :high_risk_prompt_only_count,
      :auto_deployable_count,
      :pr_review_waiting_count,
      :merge_waiting_count,
      :deploy_check_waiting_count,
      :manual_required_count
    )

    def call
      tasks = AutoRevisionTask.includes(business: :business_execution_profile)
      active_tasks = tasks.where(status: AutoRevisionTask::ACTIVE_STATUSES)
      Summary.new(
        waiting_approval_count: AutoRevisionTask.where(status: "waiting_approval").count,
        queued_count: AutoRevisionTask.where(status: %w[queued ready_for_codex sent_to_codex]).count,
        running_count: AutoRevisionTask.where(status: "running").count,
        failed_count: AutoRevisionTask.where(status: "failed").count,
        completed_today_count: AutoRevisionTask.where(status: %w[completed succeeded partial_succeeded], finished_at: Time.zone.today.all_day).count,
        high_risk_prompt_only_count: AutoRevisionTask.where(risk_level: "high", status: %w[approved ready_for_codex]).count,
        auto_deployable_count: active_tasks.select(&:auto_deploy_allowed?).size,
        pr_review_waiting_count: active_tasks.select { |task| task.status.in?(%w[queued ready_for_codex sent_to_codex]) && !task.auto_merge_allowed? }.size,
        merge_waiting_count: active_tasks.select { |task| task.status == "sent_to_codex" && task.auto_merge_allowed? }.size,
        deploy_check_waiting_count: AutoRevisionExecution.where(status: "completed", deploy_status: %w[pending deployed]).count,
        manual_required_count: active_tasks.reject(&:auto_deploy_allowed?).size
      )
    end
  end
end

class AutoRevisionTaskSummary
  Result = Data.define(
    :waiting_approval_count,
    :approved_count,
    :ready_for_codex_count,
    :sent_to_codex_count,
    :running_count,
    :stale_codex_task_count,
    :old_codex_check_count,
    :target_validation_counts,
    :exported_codex_prompt_count,
    :unexported_codex_prompt_count,
    :invalid_export_blocked_count,
    :quality_result_counts,
    :quality_approval_counts,
    :pending_quality_gate_count,
    :recent_quality_warnings,
    :recent_pending_quality_checks,
    :succeeded_count,
    :partial_succeeded_count,
    :failed_count,
    :risk_counts,
    :waiting_risk_counts,
    :waiting_total_priority_score,
    :waiting_total_expected_hours,
    :high_risk_candidate_count,
    :auto_queue_enabled,
    :last_auto_queue_at,
    :last_generated_count,
    :top_tasks,
    :codex_queue_tasks,
    :approval_queue_tasks,
    :recent_completed_tasks,
    :failed_tasks
  )

  def call
    approval_queue_tasks = AutoRevisionTask.includes(:business, :action_candidate).where(status: "waiting_approval").by_priority.limit(5)
    setting = AicooAutoRevisionSetting.current
    latest_queue_run = AutoRevisionQueueRun.recent.first
    target_validation_counts = calculate_target_validation_counts
    Result.new(
      waiting_approval_count: AutoRevisionTask.where(status: "waiting_approval").count,
      approved_count: AutoRevisionTask.where(status: "approved").count,
      ready_for_codex_count: AutoRevisionTask.where(status: "ready_for_codex").count,
      sent_to_codex_count: AutoRevisionTask.where(status: "sent_to_codex").count,
      running_count: AutoRevisionTask.where(status: "running").count,
      stale_codex_task_count: AutoRevisionTask.stale_codex.count,
      old_codex_check_count: AutoRevisionTask.codex_check_overdue.count,
      target_validation_counts:,
      exported_codex_prompt_count: exported_codex_prompt_count,
      unexported_codex_prompt_count: unexported_codex_prompt_count,
      invalid_export_blocked_count: target_validation_counts["invalid"],
      quality_result_counts: CodexQualityCheck::RESULTS.index_with { |result| CodexQualityCheck.where(result:).count },
      quality_approval_counts: CodexQualityCheck::APPROVAL_STATUSES.index_with { |status| CodexQualityCheck.where(approval_status: status).count },
      pending_quality_gate_count: CodexQualityCheck.pending_review.count,
      recent_quality_warnings: CodexQualityCheck.includes(auto_revision_task: :business).recent_warnings.limit(5),
      recent_pending_quality_checks: CodexQualityCheck.includes(auto_revision_task: :business).pending_review.order(created_at: :desc).limit(5),
      succeeded_count: AutoRevisionTask.where(status: "succeeded").count,
      partial_succeeded_count: AutoRevisionTask.where(status: "partial_succeeded").count,
      failed_count: AutoRevisionTask.where(status: "failed").count,
      risk_counts: AutoRevisionTask::RISK_LEVELS.index_with { |risk| AutoRevisionTask.where(risk_level: risk).count },
      waiting_risk_counts: AutoRevisionTask::RISK_LEVELS.index_with { |risk| AutoRevisionTask.where(status: "waiting_approval", risk_level: risk).count },
      waiting_total_priority_score: AutoRevisionTask.where(status: "waiting_approval").sum(:priority_score),
      waiting_total_expected_hours: AutoRevisionTask.where(status: "waiting_approval").includes(:action_candidate).sum { |task| task.action_candidate.expected_hours.to_d },
      high_risk_candidate_count: high_risk_candidate_count,
      auto_queue_enabled: setting.enabled?,
      last_auto_queue_at: setting.last_auto_queue_at,
      last_generated_count: latest_queue_run&.generated_tasks_count.to_i,
      top_tasks: AutoRevisionTask.includes(:business, :action_candidate).active.by_priority.limit(5),
      codex_queue_tasks: AutoRevisionTask.includes(:business, :action_candidate).codex_queue.limit(5),
      approval_queue_tasks:,
      recent_completed_tasks: AutoRevisionTask.includes(:business).where(status: %w[succeeded partial_succeeded]).order(finished_at: :desc, updated_at: :desc).limit(5),
      failed_tasks: AutoRevisionTask.includes(:business).where(status: "failed").order(finished_at: :desc, updated_at: :desc).limit(5)
    )
  end

  private

  def calculate_target_validation_counts
    counts = { "valid" => 0, "warning" => 0, "invalid" => 0 }
    AutoRevisionTask.includes(:business).where(status: AutoRevisionTask::CODEX_QUEUE_STATUSES).find_each do |task|
      counts[task.codex_prompt_target_validation.target_status] += 1
    end
    counts
  end

  def exported_codex_prompt_count
    AutoRevisionTask.where(status: AutoRevisionTask::CODEX_QUEUE_STATUSES).count do |task|
      task.metadata.to_h["last_exported_at"].present?
    end
  end

  def unexported_codex_prompt_count
    AutoRevisionTask.where(status: AutoRevisionTask::CODEX_QUEUE_STATUSES).count do |task|
      task.metadata.to_h["last_exported_at"].blank?
    end
  end

  def high_risk_candidate_count
    setting = AicooAutoRevisionSetting.current
    AicooAutoRevisionQueueBuilderService.candidate_scope.count do |candidate|
      candidate.final_score.to_d >= setting.minimum_final_score.to_d &&
        candidate.auto_revision_tasks.none? { |task| AutoRevisionTask::ACTIVE_STATUSES.include?(task.status) } &&
        AutoRevisionTask.risk_level_for(candidate) == "high"
    end
  end
end

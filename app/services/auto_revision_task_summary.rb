class AutoRevisionTaskSummary
  Result = Data.define(
    :waiting_approval_count,
    :approved_count,
    :running_count,
    :succeeded_count,
    :partial_succeeded_count,
    :failed_count,
    :risk_counts,
    :top_tasks,
    :recent_completed_tasks,
    :failed_tasks
  )

  def call
    Result.new(
      waiting_approval_count: AutoRevisionTask.where(status: "waiting_approval").count,
      approved_count: AutoRevisionTask.where(status: "approved").count,
      running_count: AutoRevisionTask.where(status: "running").count,
      succeeded_count: AutoRevisionTask.where(status: "succeeded").count,
      partial_succeeded_count: AutoRevisionTask.where(status: "partial_succeeded").count,
      failed_count: AutoRevisionTask.where(status: "failed").count,
      risk_counts: AutoRevisionTask::RISK_LEVELS.index_with { |risk| AutoRevisionTask.where(risk_level: risk).count },
      top_tasks: AutoRevisionTask.includes(:business, :action_candidate).active.by_priority.limit(5),
      recent_completed_tasks: AutoRevisionTask.includes(:business).where(status: %w[succeeded partial_succeeded]).order(finished_at: :desc, updated_at: :desc).limit(5),
      failed_tasks: AutoRevisionTask.includes(:business).where(status: "failed").order(finished_at: :desc, updated_at: :desc).limit(5)
    )
  end
end

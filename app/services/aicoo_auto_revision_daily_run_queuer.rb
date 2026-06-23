class AicooAutoRevisionDailyRunQueuer
  Result = Data.define(:ran, :queue_run, :reason)

  def call(daily_run:)
    setting = AicooAutoRevisionSetting.current
    return Result.new(ran: false, queue_run: nil, reason: "disabled") unless setting.enabled?
    return Result.new(ran: false, queue_run: nil, reason: "daily_run_not_success") unless daily_run.succeeded?

    existing_run = AutoRevisionQueueRun.find_by(aicoo_daily_run: daily_run)
    return Result.new(ran: false, queue_run: existing_run, reason: "already_run") if existing_run

    result = AicooAutoRevisionQueueBuilderService.new(
      minimum_final_score: setting.minimum_final_score,
      allow_medium_risk: setting.allow_medium_risk
    ).call(limit: setting.max_tasks_per_run)

    queue_run = AutoRevisionQueueRun.create!(
      aicoo_daily_run: daily_run,
      generated_tasks_count: result.created_count,
      skipped_candidates_count: result.skipped_count,
      high_risk_candidates_count: result.high_risk_candidates.size,
      executed_at: Time.current,
      metadata: {
        "created_task_ids" => result.created_tasks.map(&:id),
        "high_risk_candidate_ids" => result.high_risk_candidates.map(&:id),
        "minimum_final_score" => setting.minimum_final_score.to_s,
        "max_tasks_per_run" => setting.max_tasks_per_run,
        "allow_medium_risk" => setting.allow_medium_risk
      }
    )
    setting.update!(last_auto_queue_at: queue_run.executed_at)

    Result.new(ran: true, queue_run:, reason: "created")
  end
end

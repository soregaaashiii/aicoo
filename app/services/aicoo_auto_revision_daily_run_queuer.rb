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
        "reason" => queue_reason(result),
        "message" => queue_message(result),
        "candidate_count" => result.candidate_count,
        "skipped_reasons" => result.skipped_reasons.first(20),
        "created_task_ids" => result.created_tasks.map(&:id),
        "auto_revision_run_log_ids" => result.logs.map(&:id),
        "auto_revision_mode_counts" => result.logs.group_by(&:auto_revision_mode).transform_values(&:size),
        "auto_revision_status_counts" => result.logs.group_by(&:status).transform_values(&:size),
        "high_risk_candidate_ids" => result.high_risk_candidates.map(&:id),
        "minimum_final_score" => setting.minimum_final_score.to_s,
        "max_tasks_per_run" => setting.max_tasks_per_run,
        "allow_medium_risk" => setting.allow_medium_risk
      }
    )
    setting.update!(last_auto_queue_at: queue_run.executed_at)

    Result.new(ran: true, queue_run:, reason: "created")
  end

  private

  def queue_reason(result)
    return "created_tasks" if result.created_count.positive?
    return "no_eligible_candidates" if result.candidate_count.zero?
    return "all_candidates_skipped" if result.skipped_count.positive?

    "no_auto_revision_tasks_generated"
  end

  def queue_message(result)
    case queue_reason(result)
    when "created_tasks"
      "AutoRevisionTaskを#{result.created_count}件生成しました。"
    when "no_eligible_candidates"
      "AutoRevision Queueは実行されましたが、対象ステータス・実行プロンプト・スコア条件を満たすActionCandidateがありませんでした。"
    when "all_candidates_skipped"
      "AutoRevision Queueは実行されましたが、候補はすべてスコア不足または既存タスクありでスキップされました。"
    else
      "AutoRevision Queueは実行されましたが、生成件数は0件でした。"
    end
  end
end

class AicooAutoRevisionDailyRunQueuer
  Result = Data.define(:ran, :queue_run, :reason)

  def call(daily_run:)
    setting = AicooAutoRevisionSetting.current
    return Result.new(ran: false, queue_run: nil, reason: "disabled") unless setting.enabled?
    return Result.new(ran: false, queue_run: nil, reason: "daily_run_not_queueable") unless daily_run_queueable?(daily_run)

    existing_run = AutoRevisionQueueRun.find_by(aicoo_daily_run: daily_run)
    return Result.new(ran: false, queue_run: existing_run, reason: "already_run") if existing_run

    result = AicooAutoRevisionQueueBuilderService.new(
      minimum_final_score: setting.minimum_final_score,
      allow_medium_risk: setting.allow_medium_risk
    ).call(limit: setting.max_tasks_per_run)
    codex_issue_result = Aicoo::AutoRevisionCodexIssueDispatcher.new.call(
      tasks: result.created_tasks,
      limit: setting.max_tasks_per_run
    )

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
        "diagnostics" => result.diagnostics,
        "skipped_reasons" => result.skipped_reasons.first(20),
        "created_task_ids" => result.created_tasks.map(&:id),
        "auto_revision_run_log_ids" => result.logs.map(&:id),
        "auto_revision_mode_counts" => result.logs.group_by(&:auto_revision_mode).transform_values(&:size),
        "auto_revision_status_counts" => result.logs.group_by(&:status).transform_values(&:size),
        "high_risk_candidate_ids" => result.high_risk_candidates.map(&:id),
        "codex_issue_processed_count" => codex_issue_result.processed_count,
        "codex_issue_created_count" => codex_issue_result.created_issue_count,
        "codex_issue_skipped_count" => codex_issue_result.skipped_count,
        "codex_issue_failed_count" => codex_issue_result.failed_count,
        "codex_issue_details" => codex_issue_result.details.first(20),
        "minimum_final_score" => setting.minimum_final_score.to_s,
        "max_tasks_per_run" => setting.max_tasks_per_run,
        "allow_medium_risk" => setting.allow_medium_risk
      }
    )
    setting.update!(last_auto_queue_at: queue_run.executed_at)

    Result.new(ran: true, queue_run:, reason: "created")
  end

  private

  def daily_run_queueable?(daily_run)
    daily_run.status.in?(%w[success succeeded partial_failed])
  end

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
      "AutoRevision Queueは実行されましたが、対象ステータス・実行プロンプト・スコア条件を満たすActionCandidateがありませんでした。診断: #{diagnostic_summary(result)}"
    when "all_candidates_skipped"
      "AutoRevision Queueは実行されましたが、候補はすべてスコア不足・既存タスクあり・実行指示不足でスキップされました。診断: #{diagnostic_summary(result)}"
    else
      "AutoRevision Queueは実行されましたが、生成件数は0件でした。"
    end
  end

  def diagnostic_summary(result)
    diagnostics = result.diagnostics.to_h
    [
      "対象状態#{diagnostics['target_status_candidate_count']}件",
      "promptあり#{diagnostics['prompt_ready_candidate_count']}件",
      "promptなし#{diagnostics['missing_execution_prompt_count']}件",
      "score不足#{diagnostics['below_minimum_final_score_count']}件",
      "既存Taskあり#{diagnostics['active_auto_revision_task_exists_count']}件"
    ].join(" / ")
  end
end

namespace :aicoo do
  desc "Run AICOO Daily Run from cron. Usage: bundle exec rails aicoo:daily_run"
  task daily_run: :environment do
    result = Aicoo::DailyRunCronTask.call
    puts result.message

    if result.daily_run
      run = result.daily_run
      puts "daily_run_id=#{run.id}"
      puts "target_date=#{run.target_date}"
      puts "status=#{run.status}"
      puts "source=#{run.source}"
      puts "retry_count=#{run.retry_count}"
      puts "analytics_fetch_count=#{run.analytics_fetch_count}"
      puts "snapshot_count=#{run.snapshot_count}"
      puts "insight_generated_count=#{run.insight_generated_count}"
      puts "business_metrics_imported_count=#{run.business_metrics_imported_count}"
      puts "proxy_weights_adjusted_count=#{run.proxy_weights_adjusted_count}"
      puts "action_candidates_generated_count=#{run.action_candidates_generated_count}"
      puts "action_results_evaluated_count=#{run.action_results_evaluated_count}"
      puts "score_snapshots_created_count=#{run.score_snapshots_created_count}"
      puts "score_snapshot_rank_up_count=#{run.score_snapshot_rank_up_count}"
      puts "score_snapshot_rank_down_count=#{run.score_snapshot_rank_down_count}"
      puts "score_snapshot_no_adjustment_count=#{run.score_snapshot_no_adjustment_count}"
      puts "data_preparation_candidates_count=#{run.data_preparation_candidates_count}"
      puts "data_preparation_auto_queued_count=#{run.data_preparation_auto_queued_count}"
    end
  end

  desc "Dry-run cleanup of cron schedule-check skipped Daily Run rows. Use APPLY=1 to delete."
  task cleanup_daily_run_schedule_checks: :environment do
    apply = ENV.fetch("APPLY", nil).to_s == "1"
    reasons = %w[
      not_due
      already_success
      already_running
      retry_limit_reached
      disabled
      lock_not_acquired
      schedule_check_only
    ]

    scope = AicooDailyRun.where(status: "skipped")
    checked_count = scope.count
    scope = scope.left_outer_joins(:aicoo_daily_run_steps)
                 .where(aicoo_daily_run_steps: { id: nil })
    scope = scope.where(reasons.map { "run_log LIKE ?" }.join(" OR "), *reasons.map { |reason| "%#{reason}%" })

    zero_counter_columns = %w[
      analytics_fetch_count
      snapshot_count
      insight_generated_count
      business_metrics_imported_count
      proxy_weights_adjusted_count
      action_candidates_generated_count
      action_results_evaluated_count
      score_snapshots_created_count
      score_snapshot_rank_up_count
      score_snapshot_rank_down_count
      score_snapshot_no_adjustment_count
      data_preparation_candidates_count
      data_preparation_auto_queued_count
      calibration_log_count
      pending_calibration_count
      updated_calibration_count
    ] & AicooDailyRun.column_names

    zero_counter_columns.each do |column|
      scope = scope.where(column => 0)
    end

    ids = scope.reorder(:id).pluck(:id)
    deleted_count = apply ? AicooDailyRun.where(id: ids).delete_all : 0

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{checked_count}"
    puts "schedule_checks_found=#{ids.size}"
    puts "deleted=#{deleted_count}"
    puts "preserved=#{checked_count - ids.size}"
    puts "failed=0"
    puts "ids=#{ids.join(',')}" unless apply || ids.empty?
  end

  desc "Diagnose latest stuck Daily Runs. Usage: bin/rails aicoo:diagnose_stuck_daily_runs LIMIT=10"
  task diagnose_stuck_daily_runs: :environment do
    limit = ENV.fetch("LIMIT", "10").to_i
    rows = Aicoo::DailyRunStuckDiagnostic.call(limit:)

    puts "stuck_runs_checked=#{rows.size}"
    puts

    rows.each do |row|
      run = row.run
      last_step = row.last_started_step
      running_step = row.last_running_step
      successful_step = row.last_successful_step

      puts "Run #{run.id}"
      puts "status=#{run.status}"
      puts "target_date=#{run.target_date}"
      puts "source=#{run.source}"
      puts "started_at=#{run.started_at&.iso8601 || '-'}"
      puts "finished_at=#{row.finished_at&.iso8601 || '-'}"
      puts "last_successful_step=#{successful_step&.step_name || '-'}"
      puts "last_started_step=#{last_step&.step_name || '-'}"
      puts "last_step=#{running_step&.step_name || last_step&.step_name || '-'}"
      puts "last_step_status=#{running_step&.status || last_step&.status || '-'}"
      puts "elapsed=#{format_duration(row.elapsed_seconds)}"
      puts "exception=#{row.exception.presence || '-'}"
      puts "heartbeat=#{row.heartbeat.presence || '-'}"
      puts "recoverable=#{running_step&.recoverable? || false}"
      puts "=================="
      puts
    end
  end

  desc "Resume a recoverable stuck Daily Run step. Usage: RUN_ID=123 bin/rails aicoo:resume_stuck_daily_run"
  task resume_stuck_daily_run: :environment do
    run_id = ENV.fetch("RUN_ID", nil).presence
    abort "RUN_ID is required" unless run_id

    run = AicooDailyRun.find(run_id)
    step = run.aicoo_daily_run_steps.where(status: "running").recent.first ||
      run.aicoo_daily_run_steps.failed.recent.first
    abort "recoverable step not found" unless step
    if step.status == "running"
      finished_at = Time.current
      step.update!(
        status: "failed",
        finished_at:,
        duration_seconds: step.started_at ? finished_at - step.started_at : nil,
        error_message: "stuck recovery requested"
      )
    end

    result = Aicoo::StepRecoveryService.run!(daily_run: run, step_name: step.step_name)
    if result.success
      run.update!(
        status: "partial_failed",
        finished_at: result.finished_at,
        error_message: nil,
        run_log: [ run.run_log.presence, "[#{Time.current.iso8601}] Step resumed: #{step.step_name} #{result.message}" ].compact.join("\n")
      )
    end

    puts "run_id=#{run.id}"
    puts "step=#{step.step_name}"
    puts "success=#{result.success}"
    puts "message=#{result.message.presence || '-'}"
    puts "error=#{result.error_message.presence || '-'}"
  end

  def format_duration(seconds)
    seconds = seconds.to_i
    minutes = seconds / 60
    return "#{seconds}s" if minutes.zero?

    hours = minutes / 60
    remaining_minutes = minutes % 60
    return "#{minutes}m" if hours.zero?

    "#{hours}h#{remaining_minutes}m"
  end
end

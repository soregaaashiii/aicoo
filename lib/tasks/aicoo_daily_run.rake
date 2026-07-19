namespace :aicoo do
  desc "Run AICOO Daily Run from cron. Usage: bundle exec rails aicoo:daily_run"
  task daily_run: :environment do
    source = daily_run_source
    if source == "cron"
      result = Aicoo::DailyRunCronTask.call
      puts result.message
      print_daily_run(result.daily_run) if result.daily_run
    else
      Rails.logger.info("AICOO Daily Run manual schedule check started source=#{source}")
      result = AicooDailyRunScheduler.check!(source:)
      if result.is_a?(AicooDailyRun)
        puts "AICOO Daily Run manual finished: daily_run_id=#{result.id} status=#{result.status} target_date=#{result.target_date}"
        print_daily_run(result)
      else
        puts "AICOO Daily Run manual schedule check: reason=#{result.reason} target_date=#{result.target_date}"
        puts "source=#{result.source}"
      end
    end
  end

  desc "Diagnose Daily Run retry blocking. Usage: bin/rails aicoo:diagnose_daily_run_retry TARGET_DATE=2026-07-18"
  task diagnose_daily_run_retry: :environment do
    target_date = parse_daily_run_target_date
    row = Aicoo::DailyRunRetryDiagnostic.call(target_date:)

    puts "latest_run_id=#{row.latest_run&.id || '-'}"
    puts "target_date=#{row.target_date}"
    puts "run_status=#{row.latest_run&.status || '-'}"
    puts "execution_source=#{row.latest_run&.source || '-'}"
    puts "retry_count=#{row.retry_count}"
    puts "retry_limit=#{row.retry_limit}"
    puts "retry_limit_reached=#{row.retry_limit_reached}"
    puts "blocking_step_id=#{row.blocking_step&.id || '-'}"
    puts "blocking_step_name=#{row.blocking_step&.step_name || '-'}"
    puts "blocking_step_status=#{row.blocking_step&.status || '-'}"
    puts "blocking_step_retry_count=#{row.blocking_step&.recovery_attempt_count || 0}"
    puts "blocking_reason=#{row.blocking_reason || '-'}"
    puts "blocked_since=#{row.blocked_since&.iso8601 || '-'}"
    puts "active_running_run_id=#{row.active_running_run&.id || '-'}"
    puts "lock_available=#{row.active_running_run.nil?}"
    puts "manual_run_allowed=#{row.manual_run_allowed}"
    puts "cron_run_allowed=#{row.cron_run_allowed}"
    puts "recoverable_steps=#{row.recoverable_steps.map(&:step_name).join(',').presence || '-'}"
    puts "next_action=#{row.next_action}"
    puts
    puts "steps:"
    row.steps.each do |step_row|
      puts [
        "step_name=#{step_row.step_name}",
        "status=#{step_row.status}",
        "retry_count=#{step_row.retry_count}",
        "retry_limit=#{step_row.retry_limit}",
        "recoverable=#{step_row.recoverable}",
        "last_error=#{step_row.last_error.presence || '-'}",
        "started_at=#{step_row.started_at&.iso8601 || '-'}",
        "finished_at=#{step_row.finished_at&.iso8601 || '-'}",
        "next_action=#{step_row.next_action}"
      ].join(" ")
    end
  end

  desc "Dry-run manual Daily Run recovery. Use APPLY=1 to execute. Optional TARGET_STEP=article_opportunity_analysis"
  task daily_run_manual: :environment do
    apply = ENV.fetch("APPLY", nil).to_s == "1"
    target_date = parse_daily_run_target_date
    target_step = ENV.fetch("TARGET_STEP", nil).presence
    requested_by = ENV.fetch("REQUESTED_BY", "render_shell")
    result = Aicoo::DailyRunManualRunner.call(target_date:, target_step:, apply:, requested_by:)

    puts "mode=#{result.mode}"
    puts "target_date=#{result.target_date}"
    puts "source=#{result.source}"
    puts "retry_limit_bypassed=#{result.retry_limit_bypassed}"
    puts "blocking_reason=#{result.blocking_reason || '-'}"
    puts "run_id=#{result.daily_run&.id || '-'}"
    puts "run_status=#{result.daily_run&.status || '-'}"
    puts "target_steps=#{result.selected_steps.join(',').presence || '-'}"
    puts "success=#{result.success}"
    puts "message=#{result.message.presence || '-'}"
    result.executed_steps.each do |step|
      puts "executed_step=#{step.step_name} status=#{step.status} message=#{step.message.presence || '-'} error=#{step.error_message.presence || '-'}"
    end
    result.skipped_steps.each do |step|
      puts "skipped_step=#{step.step_name} status=#{step.status} message=#{step.message.presence || '-'} error=#{step.error_message.presence || '-'}"
    end
    puts "next_action=#{apply ? 'bin/rails aicoo:diagnose_daily_run_retry' : 'APPLY=1 bin/rails aicoo:daily_run_manual'}"
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

  desc "Diagnose orphan running Daily Runs. Usage: bin/rails aicoo:diagnose_orphan_daily_runs LIMIT=20"
  task diagnose_orphan_daily_runs: :environment do
    limit = ENV.fetch("LIMIT", "20").to_i
    rows = Aicoo::DailyRunStuckGuard.diagnose_orphans(limit: limit.positive? ? limit : nil)

    puts "checked=#{rows.size}"
    puts "active_running=#{rows.count { |row| !row.orphan }}"
    puts "orphan_running=#{rows.count(&:orphan)}"
    puts "timeout_minutes=#{(Aicoo::DailyRunStuckGuard.orphan_threshold / 60).to_i}"
    puts

    rows.each do |row|
      puts "run_id=#{row.run.id}"
      puts "target_date=#{row.run.target_date}"
      puts "source=#{row.run.source}"
      puts "status=#{row.run.status}"
      puts "step_name=#{row.step&.step_name || '-'}"
      puts "step_status=#{row.step&.status || '-'}"
      puts "last_heartbeat=#{row.last_heartbeat_at&.iso8601 || '-'}"
      puts "last_updated_at=#{row.last_updated_at&.iso8601 || '-'}"
      puts "stale_minutes=#{row.stale_minutes}"
      puts "orphan=#{row.orphan}"
      puts "=================="
    end
  end

  desc "Dry-run repair orphan running Daily Runs. Use APPLY=1 to update."
  task repair_orphan_daily_runs: :environment do
    apply = ENV.fetch("APPLY", nil).to_s == "1"
    rows = Aicoo::DailyRunStuckGuard.diagnose_orphans
    orphan_rows = rows.select(&:orphan)
    result = Aicoo::DailyRunStuckGuard.repair_orphan_runs!(apply:) if apply

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{rows.size}"
    puts "active_running=#{rows.count { |row| !row.orphan }}"
    puts "orphan_running=#{orphan_rows.size}"
    puts "stale_minutes=#{orphan_rows.map(&:stale_minutes).max || 0}"
    puts "repaired=#{apply ? result.stuck_count.to_i + result.partial_failed_count.to_i : 0}"
    puts "stuck=#{apply ? result.stuck_count : 0}"
    puts "partial_failed=#{apply ? result.partial_failed_count : 0}"
    puts "run_ids=#{orphan_rows.map { |row| row.run.id }.join(',')}" if orphan_rows.any?
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

  desc "Dry-run cleanup duplicate stuck Daily Runs. Use APPLY=1 to delete duplicates."
  task cleanup_duplicate_stuck_daily_runs: :environment do
    apply = ENV.fetch("APPLY", nil).to_s == "1"
    rows = Aicoo::DailyRunStuckDiagnostic.call(limit: AicooDailyRun.where(status: "stuck").count)
    groups = rows.group_by do |row|
      [
        row.run.target_date,
        row.last_running_step&.step_name || row.last_started_step&.step_name || "unknown",
        row.exception.to_s.presence || row.run.error_message.to_s.presence || "unknown"
      ]
    end

    duplicate_ids = groups.values.flat_map do |items|
      next [] if items.size <= 1

      items.sort_by { |row| row.run.id }.reverse.drop(1).map { |row| row.run.id }
    end

    deleted_count = 0
    if apply
      AicooDailyRun.where(id: duplicate_ids).find_each do |run|
        run.destroy!
        deleted_count += 1
      end
    end

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "stuck_checked=#{rows.size}"
    puts "duplicate_groups=#{groups.values.count { |items| items.size > 1 }}"
    puts "duplicates_found=#{duplicate_ids.size}"
    puts "deleted=#{deleted_count}"
    puts "ids=#{duplicate_ids.join(',')}" unless apply || duplicate_ids.empty?
  end

  def daily_run_source
    source = ENV.fetch("AICOO_RUN_SOURCE", nil).presence || ENV.fetch("SOURCE", nil).presence || "cron"
    source = source.to_s
    return source if AicooDailyRun::SOURCES.include?(source)

    "cron"
  end

  def parse_daily_run_target_date
    value = ENV.fetch("TARGET_DATE", nil).presence
    value ? Date.parse(value) : nil
  rescue ArgumentError
    abort "TARGET_DATE is invalid"
  end

  def print_daily_run(run)
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

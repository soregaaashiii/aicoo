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
end

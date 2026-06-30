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
end

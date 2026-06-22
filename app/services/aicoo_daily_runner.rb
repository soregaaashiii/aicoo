class AicooDailyRunner
  def self.run!(target_date: Date.yesterday, source: "manual")
    new(target_date:, source:).run!
  end

  def initialize(target_date: Date.yesterday, source: "manual")
    @target_date = target_date.to_date
    @source = source
    @log_lines = []
    @partial_failures = []
  end

  def run!
    existing_run = AicooDailyRun.running.find_by(target_date:)
    return existing_run if existing_run

    run = AicooDailyRun.create!(
      target_date:,
      status: "pending",
      source:,
      retry_count: retry_count_for_today
    )
    run.update!(status: "running", started_at: Time.current)

    execute_steps!(run)
    final_status = partial_failures.empty? ? "success" : "partial_failed"
    run.update!(status: final_status, finished_at: Time.current, run_log: log_text)
    AicooDailyRunSetting.current.update!(last_success_at: run.finished_at) if final_status == "success"
    run
  rescue StandardError => e
    fail_run!(run, e) if run
    raise
  end

  private

  attr_reader :target_date, :source, :log_lines, :partial_failures

  def execute_steps!(run)
    log!("Daily Run started target_date=#{target_date}")

    analytics_runs = fetch_analytics!
    analytics_success_count = analytics_runs.count { |analytics_run| analytics_run.status == "success" }
    analytics_failed_count = analytics_runs.count { |analytics_run| analytics_run.status == "failed" }
    run.update!(analytics_fetch_count: analytics_success_count)
    partial_failures << "analytics_failed=#{analytics_failed_count}" if analytics_failed_count.positive?
    log!("Analytics fetched success=#{analytics_success_count} failed=#{analytics_failed_count}")

    datahub_run = AicooDataHub::DailyCollector.new.call
    run.update!(snapshot_count: datahub_run.snapshot_count)
    log!("DataHub collected snapshots count=#{datahub_run.snapshot_count}")

    imported_results = BusinessMetricDailyImporter.import_all!(date: target_date)
    run.update!(business_metrics_imported_count: imported_results.size)
    log!("BusinessMetricDaily imported count=#{imported_results.size}")

    adjustment_logs = adjust_proxy_weights
    run.update!(proxy_weights_adjusted_count: adjustment_logs.size)
    log!("proxy_score weights checked count=#{adjustment_logs.size}")

    generation_results = MetricActionCandidateGenerator.generate_all!
    generated_count = generation_results.sum(&:created_count)
    run.update!(action_candidates_generated_count: generated_count)
    log!("ActionCandidate generated count=#{generated_count}")

    insight_result = AicooInsight::Generator.generate_all!(source: "daily_run")
    run.update!(insight_generated_count: insight_result.created_count)
    log!("Insight generated count=#{insight_result.created_count}")
    log!("Insight skipped count=#{insight_result.skipped_count}")

    evaluated_results = ActionResultEvaluator.evaluate_pending!
    run.update!(action_results_evaluated_count: evaluated_results.size)
    log!("ActionResult evaluated_or_skipped count=#{evaluated_results.size}")

    snapshot_result = ActionCandidateScoreSnapshotter.new.snapshot_top_candidates!(date: target_date)
    run.update!(
      score_snapshots_created_count: snapshot_result.created_count,
      score_snapshot_rank_up_count: snapshot_result.rank_up_count,
      score_snapshot_rank_down_count: snapshot_result.rank_down_count,
      score_snapshot_no_adjustment_count: snapshot_result.no_adjustment_count
    )
    log!(
      "ActionCandidate score snapshots created count=#{snapshot_result.created_count} " \
      "rank_up=#{snapshot_result.rank_up_count} " \
      "rank_down=#{snapshot_result.rank_down_count} " \
      "no_adjustment=#{snapshot_result.no_adjustment_count}"
    )

    queue_result = DataPreparationExecutorQueuer.new.call
    run.update!(
      data_preparation_candidates_count: queue_result.candidate_count,
      data_preparation_auto_queued_count: queue_result.queued_count
    )
    log!("Data preparation candidates: #{queue_result.candidate_count}")
    log!("Auto queued: #{queue_result.queued_count}")
    log!("Skipped: #{queue_result.skipped_count}")
    log!("Reason: #{queue_result.skipped_reasons.map { |reason, count| "#{reason}=#{count}" }.join(', ')}")

    meta_snapshot_result = MetaEvaluationSnapshotter.new.snapshot!(date: target_date, aicoo_daily_run: run)
    log!("MetaEvaluationSnapshot created count=#{meta_snapshot_result.created_count}")
    log!("Most trusted evaluator: #{meta_snapshot_result.top_evaluator || 'none'}")
    MetaEvaluationSnapshot::EVALUATOR_TYPES.each do |evaluator_type|
      confidence = meta_snapshot_result.confidence_by_type.fetch(evaluator_type).round(1)
      log!("#{evaluator_type.upcase} average confidence=#{confidence}")
    end

    log!("Daily Run finished target_date=#{target_date}")
  end

  def fetch_analytics!
    before_ids = AnalyticsFetchRun.pluck(:id)
    AicooAnalytics::DailyFetchJob.perform_now
    AnalyticsFetchRun.where.not(id: before_ids)
  end

  def adjust_proxy_weights
    adjuster = ProxyScoreWeightAdjuster.new
    start_date = target_date - 30
    business_logs = adjuster.adjust_all_businesses!(start_date:, end_date: target_date)
    return business_logs unless global_adjustable?

    business_logs + [ adjuster.adjust_global!(start_date:, end_date: target_date) ]
  end

  def global_adjustable?
    BusinessMetricDaily.count >= 90 && RevenueEvent.revenue.count >= 20
  end

  def fail_run!(run, error)
    log!("Daily Run failed: #{error.class}: #{error.message}")
    run.update!(
      status: "failed",
      finished_at: Time.current,
      error_message: "#{error.class}: #{error.message}",
      run_log: log_text
    )
  end

  def log!(message)
    log_lines << "[#{Time.current.iso8601}] #{message}"
  end

  def log_text
    log_lines.join("\n")
  end

  def retry_count_for_today
    AicooDailyRun.where(target_date:).where.not(status: "skipped").count
  end
end

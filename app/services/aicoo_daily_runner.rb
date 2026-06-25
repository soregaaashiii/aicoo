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
    if final_status == "success"
      run_auto_revision_queue!(run)
      run.update!(run_log: log_text)
      AicooDailyRunSetting.current.update!(last_success_at: run.finished_at)
    end
    run
  rescue StandardError => e
    fail_run!(run, e) if run
    raise
  end

  private

  attr_reader :target_date, :source, :log_lines, :partial_failures

  def execute_steps!(run)
    log!("Daily Run started target_date=#{target_date}")

    analytics_step = start_step!(run, "analytics_fetch")
    analytics_runs = fetch_analytics!
    analytics_success_count = analytics_runs.count { |analytics_run| analytics_run.status == "success" }
    analytics_failed_count = analytics_runs.count { |analytics_run| analytics_run.status == "failed" }
    run.update!(analytics_fetch_count: analytics_success_count)
    partial_failures << "analytics_failed=#{analytics_failed_count}" if analytics_failed_count.positive?
    if analytics_failed_count.positive?
      fail_step!(
        analytics_step,
        "analytics_failed=#{analytics_failed_count}",
        metadata: { success_count: analytics_success_count, failed_count: analytics_failed_count }
      )
    else
      finish_step!(
        analytics_step,
        metadata: { success_count: analytics_success_count, failed_count: analytics_failed_count }
      )
    end
    log!("Analytics fetched success=#{analytics_success_count} failed=#{analytics_failed_count}")

    datahub_run = record_step!(run, "datahub_collect") do
      AicooDataHub::DailyCollector.new.call
    end
    run.update!(snapshot_count: datahub_run.snapshot_count)
    log!("DataHub collected snapshots count=#{datahub_run.snapshot_count}")

    imported_results = record_step!(run, "business_metrics_import") do
      BusinessMetricDailyImporter.import_all!(date: target_date)
    end
    run.update!(business_metrics_imported_count: imported_results.size)
    log!("BusinessMetricDaily imported count=#{imported_results.size}")

    adjustment_logs = record_step!(run, "proxy_weight_adjustment") do
      adjust_proxy_weights
    end
    run.update!(proxy_weights_adjusted_count: adjustment_logs.size)
    log!("proxy_score weights checked count=#{adjustment_logs.size}")

    generation_results = record_step!(run, "action_generation") do
      MetricActionCandidateGenerator.generate_all!
    end
    generated_count = generation_results.sum(&:created_count)
    run.update!(action_candidates_generated_count: generated_count)
    log!("ActionCandidate generated count=#{generated_count}")

    insight_result = record_step!(run, "insight_generation") do
      AicooInsight::Generator.generate_all!(source: "daily_run")
    end
    run.update!(insight_generated_count: insight_result.created_count)
    log!("Insight generated count=#{insight_result.created_count}")
    log!("Insight skipped count=#{insight_result.skipped_count}")

    explore_opportunity_result = record_step!(run, "explore_opportunity_generation") do
      Aicoo::ExploreOpportunityGenerator.generate_all_pending!
    end
    log!("Explore Opportunity generated count=#{explore_opportunity_result.created.size}")
    log!("Explore Opportunity skipped count=#{explore_opportunity_result.skipped.size}")

    evaluated_results = record_step!(run, "action_result_evaluation") do
      ActionResultEvaluator.evaluate_pending!
    end
    run.update!(action_results_evaluated_count: evaluated_results.size)
    log!("ActionResult evaluated_or_skipped count=#{evaluated_results.size}")

    snapshot_result = record_step!(run, "score_snapshot") do
      ActionCandidateScoreSnapshotter.new.snapshot_top_candidates!(date: target_date)
    end
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

    queue_result = record_step!(run, "data_preparation_queue") do
      DataPreparationExecutorQueuer.new.call
    end
    run.update!(
      data_preparation_candidates_count: queue_result.candidate_count,
      data_preparation_auto_queued_count: queue_result.queued_count
    )
    log!("Data preparation candidates: #{queue_result.candidate_count}")
    log!("Auto queued: #{queue_result.queued_count}")
    log!("Skipped: #{queue_result.skipped_count}")
    log!("Reason: #{queue_result.skipped_reasons.map { |reason, count| "#{reason}=#{count}" }.join(', ')}")

    meta_snapshot_result = record_step!(run, "meta_evaluation_snapshot") do
      MetaEvaluationSnapshotter.new.snapshot!(date: target_date, aicoo_daily_run: run)
    end
    log!("MetaEvaluationSnapshot created count=#{meta_snapshot_result.created_count}")
    log!("Most trusted evaluator: #{meta_snapshot_result.top_evaluator || 'none'}")
    MetaEvaluationSnapshot::EVALUATOR_TYPES.each do |evaluator_type|
      confidence = meta_snapshot_result.confidence_by_type.fetch(evaluator_type).round(1)
      log!("#{evaluator_type.upcase} average confidence=#{confidence}")
    end

    run_calibration!(run)

    record_step!(run, "owner_task_digest") do
      Aicoo::OwnerTaskDigest.new.call
    end

    owner_queue_result = record_step!(run, "owner_execution_queue") do
      Aicoo::OwnerExecutionQueueBuilder.new(due_on: Date.current, generated_from: "daily_run").call
    end
    log!("OwnerExecutionQueue created count=#{owner_queue_result.created.size}")
    log!("OwnerExecutionQueue skipped count=#{owner_queue_result.skipped.size}")
    log!("OwnerExecutionQueue high risk count=#{owner_queue_result.high_risk.size}")

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

  def run_calibration!(run)
    started_at = Time.current
    step = start_step!(run, "calibration")
    run.update!(calibration_started_at: started_at, calibration_error: nil)
    log!("Calibration started")
    result = Aicoo::CalibrationEngine.run!(source: "daily_run", aicoo_daily_run: run)
    finished_at = Time.current
    run.update!(
      calibration_ran: true,
      calibration_finished_at: finished_at,
      updated_calibration_count: result.calibration_count,
      calibration_log_count: result.logs.size,
      pending_calibration_count: result.pending_count
    )
    finish_step!(
      step,
      metadata: {
        updated_calibration_count: result.calibration_count,
        calibration_log_count: result.logs.size,
        pending_calibration_count: result.pending_count
      }
    )
    log!(
      "Calibration finished updated_calibration_count=#{result.calibration_count} " \
      "created_log_count=#{result.logs.size} " \
      "pending_calibration_count=#{result.pending_count}"
    )
  rescue StandardError => e
    finished_at = Time.current
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run calibration failed: #{error_message}")
    partial_failures << "calibration_failed"
    run.update!(
      calibration_ran: false,
      calibration_finished_at: finished_at,
      calibration_error: error_message
    )
    fail_step!(step, error_message) if step
    log!("Calibration failed: #{error_message}")
  end

  def run_auto_revision_queue!(run)
    step = start_step!(run, "auto_revision_queue")
    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run: run)
    case result.reason
    when "created"
      finish_step!(
        step,
        metadata: {
          generated_tasks_count: result.queue_run.generated_tasks_count,
          skipped_candidates_count: result.queue_run.skipped_candidates_count,
          high_risk_candidates_count: result.queue_run.high_risk_candidates_count
        }
      )
      log!(
        "AutoRevisionQueue generated=#{result.queue_run.generated_tasks_count} " \
        "skipped=#{result.queue_run.skipped_candidates_count} " \
        "high_risk=#{result.queue_run.high_risk_candidates_count}"
      )
    when "already_run"
      skip_step!(step, metadata: { reason: "already_run" })
      log!("AutoRevisionQueue skipped reason=already_run")
    when "disabled"
      skip_step!(step, metadata: { reason: "disabled" })
      log!("AutoRevisionQueue skipped reason=disabled")
    else
      skip_step!(step, metadata: { reason: result.reason })
      log!("AutoRevisionQueue skipped reason=#{result.reason}")
    end
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run auto revision queue failed: #{error_message}")
    fail_step!(step, error_message) if step
    log!("AutoRevisionQueue failed: #{error_message}")
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

  def record_step!(run, step_name)
    step = start_step!(run, step_name)
    result = yield
    finish_step!(step)
    result
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def start_step!(run, step_name)
    run.aicoo_daily_run_steps.create!(
      step_name:,
      status: "running",
      started_at: Time.current
    )
  end

  def finish_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "success",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: metadata
    )
  end

  def fail_step!(step, error_message, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "failed",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      error_message:,
      metadata: metadata
    )
  end

  def skip_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "skipped",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: metadata
    )
  end

  def step_duration(step, finished_at)
    return unless step.started_at

    finished_at - step.started_at
  end

  def retry_count_for_today
    AicooDailyRun.where(target_date:).where.not(status: "skipped").count
  end
end

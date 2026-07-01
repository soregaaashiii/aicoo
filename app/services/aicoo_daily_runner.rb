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
      run_pipeline_stuck_detector!(run)
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
    analytics_failed_runs = analytics_runs.select { |analytics_run| analytics_run.status == "failed" }
    analytics_failed_count = analytics_failed_runs.size
    analytics_blocking_failures = analytics_failed_runs.reject { |analytics_run| non_blocking_analytics_failure?(analytics_run) }
    run.update!(analytics_fetch_count: analytics_success_count)
    partial_failures << "analytics_failed=#{analytics_blocking_failures.size}" if analytics_blocking_failures.any?
    if analytics_blocking_failures.any?
      fail_step!(
        analytics_step,
        "analytics_failed=#{analytics_blocking_failures.size}",
        metadata: analytics_metadata(
          success_count: analytics_success_count,
          failed_runs: analytics_failed_runs,
          blocking_failures: analytics_blocking_failures
        )
      )
    elsif analytics_failed_count.positive?
      skip_step!(
        analytics_step,
        metadata: analytics_metadata(
          success_count: analytics_success_count,
          failed_runs: analytics_failed_runs,
          blocking_failures: analytics_blocking_failures
        ).merge(
          warning: true,
          reason: "analytics_optional_unavailable",
          message: "GA4/GSC取得は失敗しましたが、内部データによるDaily Runは継続しました。Google再認証またはProperty設定を確認してください。"
        )
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

    run_serp_optional_steps!(run)

    run_source_app_diff_detection!(run)

    adjustment_logs = record_step!(run, "proxy_weight_adjustment") do
      adjust_proxy_weights
    end
    run.update!(proxy_weights_adjusted_count: adjustment_logs.size)
    log!("proxy_score weights checked count=#{adjustment_logs.size}")

    generation_results = run_action_generation!(run)
    generated_count = generation_results.sum(&:created_count)
    run.update!(action_candidates_generated_count: generated_count)
    log!("ActionCandidate generated count=#{generated_count}")
    log!(
      "ActionCandidate skipped reasons=#{generation_results.flat_map(&:skipped).first(10).join(' | ')}"
    ) if generated_count.zero?

    insight_result = run_insight_generation!(run)
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

    run_activity_log_evaluation_queue_build!(run)

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

    analysis_result = record_step!(run, "analysis_orchestration") do
      Aicoo::AnalysisOrchestrator.run_all!(today: Date.current, limit_per_business: 8, collect_records: false)
    end
    log!("AnalysisCandidate created count=#{analysis_result.created_count}")
    log!("AnalysisCandidate updated count=#{analysis_result.updated_count}")
    log!("AnalysisCandidate skipped count=#{analysis_result.skipped_count}")

    playbook_result = record_step!(run, "business_playbook_update") do
      Aicoo::BusinessPlaybookBuilder.update_all!(collect_records: false)
    end
    log!("BusinessPlaybook updated count=#{playbook_result.updated_count}")

    system_mode_snapshot = record_step!(run, "system_mode_snapshot") do
      Aicoo::SystemModeSnapshotBuilder.new.call
    end
    log!(
      "SystemModeSnapshot created id=#{system_mode_snapshot.id} " \
      "health_score=#{system_mode_snapshot.health_score} " \
      "critical=#{system_mode_snapshot.critical_count} " \
      "warning=#{system_mode_snapshot.warning_count}"
    )

    run_resource_aware_auto_builder!(run)

    log!("Daily Run finished target_date=#{target_date}")
  end

  def fetch_analytics!
    last_id = AnalyticsFetchRun.maximum(:id).to_i
    AicooAnalytics::DailyFetchJob.perform_now
    AnalyticsFetchRun.where("id > ?", last_id)
  end

  def analytics_metadata(success_count:, failed_runs:, blocking_failures:)
    {
      success_count:,
      failed_count: failed_runs.size,
      blocking_failed_count: blocking_failures.size,
      failed_source_types: failed_runs.map(&:source_type).compact.uniq,
      failed_messages: failed_runs.filter_map(&:error_message).first(5)
    }
  end

  def non_blocking_analytics_failure?(analytics_run)
    message = analytics_run.error_message.to_s
    return true if message.blank?

    non_blocking_patterns.any? { |pattern| message.match?(pattern) }
  end

  def non_blocking_patterns
    [
      /invalid_grant/i,
      /expired or revoked/i,
      /refresh token/i,
      /oauth_connected_at=missing/i,
      /credentials_json_source=missing/i,
      /missing/i,
      /未設定/,
      /not configured/i,
      /property.*blank/i,
      /site.*blank/i
    ]
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

  def run_serp_optional_steps!(run)
    optional_mode = Aicoo::Serp::OptionalMode.call
    return unless optional_mode.missing_key?

    optional_mode.dependent_steps.each do |step_name|
      step = start_step!(run, step_name)
      skip_step!(
        step,
        metadata: {
          reason: optional_mode.reason,
          message: optional_mode.message,
          continued_steps: optional_mode.independent_steps
        }
      )
    end
    log!("SERP optional mode: #{optional_mode.message}")
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

  def run_action_generation!(run)
    step = start_step!(run, "action_generation")
    results = MetricActionCandidateGenerator.generate_all!
    generated_count = results.sum(&:created_count)
    skipped_reasons = results.flat_map(&:skipped)
    metadata = {
      created_count: generated_count,
      skipped_count: results.sum(&:skipped_count),
      result_count: results.size,
      skipped_reasons: skipped_reasons.first(20)
    }
    if generated_count.zero?
      metadata = metadata.merge(
        warning: true,
        reason: "no_action_candidates_generated",
        message: action_generation_zero_message(skipped_reasons)
      )
    end
    finish_step!(step, metadata:)
    results
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def action_generation_zero_message(skipped_reasons)
    return "ActionCandidate Generatorは実行されましたが、生成対象Businessがないか、生成条件に一致しませんでした。" if skipped_reasons.blank?

    "ActionCandidate Generatorは実行されましたが0件でした。理由: #{skipped_reasons.first(5).join(' / ')}"
  end

  def run_insight_generation!(run)
    step = start_step!(run, "insight_generation")
    result = AicooInsight::Generator.generate_all!(source: "daily_run")
    skipped_reasons = result.skipped.map(&:to_s)
    metadata = {
      created_count: result.created_count,
      skipped_count: result.skipped_count,
      skipped_reasons: skipped_reasons.first(20)
    }
    if result.created_count.zero?
      metadata = metadata.merge(
        warning: true,
        reason: "no_insights_generated",
        message: insight_generation_zero_message(skipped_reasons)
      )
    end
    finish_step!(step, metadata:)
    result
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def insight_generation_zero_message(skipped_reasons)
    return "Insight Generatorは実行されましたが、生成条件に一致するBusinessがありませんでした。" if skipped_reasons.blank?

    "Insight Generatorは実行されましたが0件でした。理由: #{skipped_reasons.first(5).join(' / ')}"
  end

  def run_auto_revision_queue!(run)
    step = start_step!(run, "auto_revision_queue")
    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run: run)
    case result.reason
    when "created"
      metadata = {
        generated_tasks_count: result.queue_run.generated_tasks_count,
        skipped_candidates_count: result.queue_run.skipped_candidates_count,
        high_risk_candidates_count: result.queue_run.high_risk_candidates_count
      }.merge(result.queue_run.metadata.to_h.slice(
        "reason",
        "message",
        "skipped_reasons",
        "candidate_count",
        "minimum_final_score",
        "max_tasks_per_run"
      ))
      if result.queue_run.generated_tasks_count.to_i.zero?
        metadata = metadata.merge(
          warning: true,
          reason: metadata["reason"].presence || "no_auto_revision_tasks_generated",
          message: metadata["message"].presence || "AutoRevision Queueは実行されましたが、投入できる改善候補がありませんでした。"
        )
      end
      finish_step!(
        step,
        metadata:
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

  def run_pipeline_stuck_detector!(run)
    step = start_step!(run, "pipeline_stuck_detection")
    result = Aicoo::PipelineStuckDetector.new(auto_recover: true).call
    finish_step!(
      step,
      metadata: {
        checked_count: result.checked_count,
        stuck_count: result.stuck_runs.size,
        recovered_count: result.recovered_logs.size
      }
    )
    log!(
      "PipelineStuckDetector checked=#{result.checked_count} " \
      "stuck=#{result.stuck_runs.size} recovered=#{result.recovered_logs.size}"
    )
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run pipeline stuck detector failed: #{error_message}")
    fail_step!(step, error_message) if step
    log!("PipelineStuckDetector failed: #{error_message}")
  end

  def run_source_app_diff_detection!(run)
    step = start_step!(run, "source_app_diff_detection")
    result = Aicoo::SourceAppDiffDetector.new.call
    finish_step!(
      step,
      metadata: {
        created_count: result.created_count,
        skipped_count: result.skipped_count,
        error_count: result.error_count
      }
    )
    log!(
      "SourceAppDiffDetection created=#{result.created_count} " \
      "skipped=#{result.skipped_count} errors=#{result.error_count}"
    )
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run source app diff detection failed: #{error_message}")
    partial_failures << "source_app_diff_detection_failed"
    fail_step!(step, error_message) if step
    log!("SourceAppDiffDetection failed: #{error_message}")
  end

  def run_activity_log_evaluation_queue_build!(run)
    step = start_step!(run, "activity_log_evaluation_queue_build")
    result = Aicoo::ActivityEvaluationBuilder.new.call
    finish_step!(
      step,
      metadata: {
        created_count: result.created_count,
        evaluated_count: result.evaluated_count,
        skipped_count: result.skipped_count,
        pending_count: result.pending_count
      }
    )
    log!(
      "ActivityEvaluation created=#{result.created_count} evaluated=#{result.evaluated_count} " \
      "skipped=#{result.skipped_count} pending=#{result.pending_count}"
    )
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run activity evaluation failed: #{error_message}")
    partial_failures << "activity_log_evaluation_failed"
    fail_step!(step, error_message) if step
    log!("ActivityEvaluation failed: #{error_message}")
  end

  def run_resource_aware_auto_builder!(run)
    step = start_step!(run, "resource_aware_auto_build")
    result = Aicoo::ResourceAwareAutoBuilder.new(today: target_date).call(daily_run: run)
    metadata = result.diagnostics.merge(
      "budget_auto_build_enabled" => result.budget.auto_build_enabled?,
      "codex_waiting_count" => result.budget.codex_waiting_count,
      "build_queue_count" => result.budget.build_queue_count,
      "remaining_budget_yen" => result.budget.remaining_budget_yen.to_s
    )
    if result.budget.auto_build_enabled?
      finish_step!(step, metadata:)
    else
      skip_step!(step, metadata: metadata.merge(
        reason: "auto_build_disabled",
        message: "Auto BuildはOFFです。Resource BudgetでONにするとDaily Run末尾でMVP生成候補を作成します。"
      ))
    end
    log!("ResourceAwareAutoBuilder created=#{result.created_count} skipped=#{result.skipped_count}")
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run resource aware auto build failed: #{error_message}")
    fail_step!(step, error_message) if step
    log!("ResourceAwareAutoBuilder failed: #{error_message}")
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
      started_at: Time.current,
      metadata: { "memory_start" => memory_snapshot }.compact
    )
  end

  def finish_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "success",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: step_metadata_with_memory(step, metadata)
    )
    compact_memory!
  end

  def fail_step!(step, error_message, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "failed",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      error_message:,
      metadata: step_metadata_with_memory(step, metadata)
    )
    compact_memory!
  end

  def skip_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "skipped",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: step_metadata_with_memory(step, metadata)
    )
    compact_memory!
  end

  def step_duration(step, finished_at)
    return unless step.started_at

    finished_at - step.started_at
  end

  def step_metadata_with_memory(step, metadata)
    merged = step.metadata.to_h.merge(metadata.deep_stringify_keys)
    finish_memory = memory_snapshot
    merged["memory_finish"] = finish_memory if finish_memory.present?
    memory_delta = memory_delta_mb(merged)
    merged["memory_delta_mb"] = memory_delta if memory_delta
    merged
  end

  def memory_delta_mb(metadata)
    start_mb = metadata.dig("memory_start", "rss_mb")
    finish_mb = metadata.dig("memory_finish", "rss_mb")
    return if start_mb.blank? || finish_mb.blank?

    (finish_mb.to_d - start_mb.to_d).round(1).to_s
  end

  def memory_snapshot
    rss_kb = current_rss_kb
    return {} unless rss_kb

    {
      "rss_mb" => (rss_kb.to_d / 1024).round(1).to_s,
      "sampled_at" => Time.current.iso8601
    }
  end

  def current_rss_kb
    linux_rss_kb || ps_rss_kb
  rescue StandardError => e
    Rails.logger.debug("AICOO Daily Run memory sampling skipped: #{e.class}: #{e.message}")
    nil
  end

  def linux_rss_kb
    return unless File.exist?("/proc/self/status")

    line = File.foreach("/proc/self/status").find { |item| item.start_with?("VmRSS:") }
    line.to_s[/\d+/]&.to_i
  end

  def ps_rss_kb
    output = IO.popen([ "ps", "-o", "rss=", "-p", Process.pid.to_s ], &:read)
    output.to_s.strip.presence&.to_i
  end

  def compact_memory!
    return if ENV["AICOO_DAILY_RUN_GC_BETWEEN_STEPS"] == "false"

    GC.start
  end

  def retry_count_for_today
    AicooDailyRun.where(target_date:).where.not(status: "skipped").count
  end
end

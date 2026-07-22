require "zlib"

class AicooDailyRunner
  MAX_RUN_LOG_LINES = 200
  MAX_RUN_LOG_LINE_LENGTH = 300
  MAX_STEP_MEMORY_EVENTS = 20
  MAX_METADATA_HASH_KEYS = 30
  MAX_METADATA_ARRAY_ITEMS = 20
  MAX_METADATA_STRING_LENGTH = 500
  PROGRESS_BATCH_SIZE = 25

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
    return create_duplicate_skipped_run!(reason: "daily_run_lock_not_acquired") unless acquire_daily_run_lock

    run_with_lock
  ensure
    release_daily_run_lock if @daily_run_lock_acquired
  end

  private

  attr_reader :target_date, :source, :log_lines, :partial_failures

  def run_with_lock
    run = nil
    Aicoo::DailyRunStuckGuard.repair_orphan_runs!(target_date:)
    existing_run = Aicoo::DailyRunStuckGuard.active_running_run_for(target_date)
    return create_duplicate_skipped_run!(reason: "already_running", existing_run:) if existing_run

    run = AicooDailyRun.create!(
      target_date:,
      status: "pending",
      source:,
      retry_count: retry_count_for_today
    )
    run.update!(status: "running", started_at: Time.current)

    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner#run!", context: daily_run_memory_context(run)) do
      execute_steps!(run)
      final_status = partial_failures.empty? ? "success" : "partial_failed"
      run.update!(status: final_status, finished_at: Time.current, run_log: log_text)
      if auto_revision_queueable_status?(final_status)
        run_auto_revision_queue!(run)
        run_pipeline_stuck_detector!(run)
        run.update!(run_log: log_text)
      end
      if final_status == "success"
        AicooDailyRunSetting.current.update!(last_success_at: run.finished_at)
      end
    end
    run
  rescue StandardError => e
    fail_run!(run, e) if run
    raise
  end

  def auto_revision_queueable_status?(status)
    status.in?(%w[success partial_failed])
  end

  def acquire_daily_run_lock
    return true unless postgresql_adapter?

    value = ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(#{daily_run_lock_key})")
    @daily_run_lock_acquired = truthy_database_value?(value)
  rescue StandardError => e
    Rails.logger.error("[AicooDailyRunner] daily_run_lock acquire failed target_date=#{target_date}: #{e.class}: #{e.message}")
    raise
  end

  def release_daily_run_lock
    return unless postgresql_adapter?

    ActiveRecord::Base.connection.select_value("SELECT pg_advisory_unlock(#{daily_run_lock_key})")
  rescue StandardError => e
    Rails.logger.warn("[AicooDailyRunner] daily_run_lock release failed target_date=#{target_date}: #{e.class}: #{e.message}")
  ensure
    @daily_run_lock_acquired = false
  end

  def postgresql_adapter?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def daily_run_lock_key
    @daily_run_lock_key ||= Zlib.crc32("aicoo_daily_run:#{target_date}")
  end

  def truthy_database_value?(value)
    value == true || value.to_s == "t" || value.to_s == "true" || value.to_s == "1"
  end

  def create_duplicate_skipped_run!(reason:, existing_run: nil)
    finished_at = Time.current
    AicooDailyRun.create!(
      target_date:,
      status: "duplicate_skipped",
      source:,
      retry_count: retry_count_for_today,
      started_at: finished_at,
      finished_at:,
      run_log: duplicate_skipped_log(reason:, existing_run:, finished_at:)
    )
  end

  def duplicate_skipped_log(reason:, existing_run:, finished_at:)
    parts = [
      "[#{finished_at.iso8601}] Daily Run duplicate_skipped",
      "reason=#{reason}",
      "target_date=#{target_date}",
      "source=#{source}"
    ]
    parts << "existing_run_id=#{existing_run.id}" if existing_run
    parts.join(" ")
  end

  def execute_steps!(run)
    log!("Daily Run started target_date=#{target_date}")

    analytics_step = start_step!(run, "analytics_fetch")
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.analytics_fetch", context: daily_run_memory_context(run, step_name: "analytics_fetch", step_id: analytics_step.id)) do
      record_step_progress!(analytics_step, batch: 0, processed: 0)
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
      analytics_runs = analytics_failed_runs = analytics_blocking_failures = nil
    end

    datahub_run = record_step!(run, "datahub_collect") do
      AicooDataHub::DailyCollector.new.call
    end
    run.update!(snapshot_count: datahub_run.snapshot_count)
    log!("DataHub collected snapshots count=#{datahub_run.snapshot_count}")
    datahub_run = nil

    imported_results = run_business_metrics_import!(run)
    log!("BusinessMetricDaily imported count=#{imported_results.size}")
    imported_results = nil

    run_activity_log_evaluation_queue_build!(run)

    run_suelog_database_steps!(run)

    article_opportunity_result = run_article_opportunity_analysis!(run)
    log!(
      "ArticleOpportunityAnalysis status=#{article_opportunity_result.status} " \
      "snapshots_created=#{article_opportunity_result.snapshot_result&.created_count.to_i} " \
      "analyzed=#{article_opportunity_result.analyzer_result&.analyzed_count.to_i} " \
      "candidates_created=#{article_opportunity_result.candidate_created_count} " \
      "promoted=#{article_opportunity_result.proposal_promoted_count} " \
      "today_eligible=#{article_opportunity_result.today_eligible_count}"
    )
    article_opportunity_result = nil

    landing_page_result = record_step!(run, "landing_page_opportunity_analysis") do
      Aicoo::LpIntegration::LandingPageImprovementBatchAnalyzer.call
    end
    log!(
      "LandingPageOpportunityAnalysis businesses=#{landing_page_result.business_count} " \
      "landing_pages=#{landing_page_result.landing_page_count} analyzed=#{landing_page_result.analyzed_count} " \
      "candidates=#{landing_page_result.candidate_count} failed=#{landing_page_result.failed_count}"
    )
    landing_page_result = nil

    run_source_app_diff_detection!(run)

    adjustment_logs = record_step!(run, "proxy_weight_adjustment") do
      adjust_proxy_weights
    end
    run.update!(proxy_weights_adjusted_count: adjustment_logs.size)
    log!("proxy_score weights checked count=#{adjustment_logs.size}")
    adjustment_logs = nil

    generation_results = run_action_generation!(run)
    generated_count = generation_results.created_count
    run.update!(action_candidates_generated_count: generated_count)
    log!("ActionCandidate generated count=#{generated_count}")
    log!(
      "ActionCandidate skipped reasons=#{generation_results.skipped.first(10).join(' | ')}"
    ) if generated_count.zero?
    generation_results = nil

    insight_result = run_insight_generation!(run)
    run.update!(insight_generated_count: insight_result.created_count)
    log!("Insight generated count=#{insight_result.created_count}")
    log!("Insight skipped count=#{insight_result.skipped_count}")
    insight_result = nil

    explore_opportunity_result = record_step!(run, "explore_opportunity_generation") do
      Aicoo::ExploreOpportunityGenerator.generate_all_pending!
    end
    log!("Explore Opportunity generated count=#{explore_opportunity_result.created.size}")
    log!("Explore Opportunity skipped count=#{explore_opportunity_result.skipped.size}")
    explore_opportunity_result = nil

    evaluated_results = record_step!(run, "action_result_evaluation") do
      ActionResultEvaluator.evaluate_pending!
    end
    run.update!(action_results_evaluated_count: evaluated_results.size)
    log!("ActionResult evaluated_or_skipped count=#{evaluated_results.size}")
    evaluated_results = nil

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
    snapshot_result = nil

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
    queue_result = nil

    meta_snapshot_result = record_step!(run, "meta_evaluation_snapshot") do
      MetaEvaluationSnapshotter.new.snapshot!(date: target_date, aicoo_daily_run: run)
    end
    log!("MetaEvaluationSnapshot created count=#{meta_snapshot_result.created_count}")
    log!("Most trusted evaluator: #{meta_snapshot_result.top_evaluator || 'none'}")
    MetaEvaluationSnapshot::EVALUATOR_TYPES.each do |evaluator_type|
      confidence = meta_snapshot_result.confidence_by_type.fetch(evaluator_type).round(1)
      log!("#{evaluator_type.upcase} average confidence=#{confidence}")
    end
    meta_snapshot_result = nil

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
    owner_queue_result = nil

    analysis_result = record_step!(run, "analysis_orchestration") do
      Aicoo::AnalysisOrchestrator.run_all!(today: Date.current, limit_per_business: 8, collect_records: false)
    end
    log!("AnalysisCandidate created count=#{analysis_result.created_count}")
    log!("AnalysisCandidate updated count=#{analysis_result.updated_count}")
    log!("AnalysisCandidate skipped count=#{analysis_result.skipped_count}")
    analysis_result = nil

    playbook_result = record_step!(run, "business_playbook_update") do
      Aicoo::BusinessPlaybookBuilder.update_all!(collect_records: false)
    end
    log!("BusinessPlaybook updated count=#{playbook_result.updated_count}")
    playbook_result = nil

    traffic_channel_result = record_step!(run, "traffic_channel_recording") do
      Aicoo::TrafficChannels::DailyRecorder.record!(daily_run: run)
    end
    log!(
      "TrafficChannel recorded=#{traffic_channel_result.recorded_count} " \
      "skipped=#{traffic_channel_result.skipped_count}"
    )
    traffic_channel_result = nil

    system_mode_snapshot = record_step!(run, "system_mode_snapshot") do
      Aicoo::SystemModeSnapshotBuilder.new.call
    end
    log!(
      "SystemModeSnapshot created id=#{system_mode_snapshot.id} " \
      "health_score=#{system_mode_snapshot.health_score} " \
      "critical=#{system_mode_snapshot.critical_count} " \
      "warning=#{system_mode_snapshot.warning_count}"
    )
    system_mode_snapshot = nil

    run_resource_aware_auto_builder!(run)

    log!("Daily Run finished target_date=#{target_date}")
  end

  def fetch_analytics!
    last_id = AnalyticsFetchRun.maximum(:id).to_i
    AicooAnalytics::DailyFetchJob.perform_now
    AnalyticsFetchRun.where("id > ?", last_id)
  end

  def run_business_metrics_import!(run)
    step = start_step!(run, "business_metrics_import")
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.business_metrics_import", context: daily_run_memory_context(run, step_name: "business_metrics_import", step_id: step.id)) do
      record_step_progress!(step, batch: 0, processed: 0)
      log!("business_metrics_import start target_date=#{target_date}")
      imported_results = BusinessMetricDailyImporter.import_all!(
        date: target_date,
        progress: business_metrics_progress_callback(step)
      )
      metadata = {
        "processed_business_count" => imported_results.processed_count,
        "created_count" => imported_results.created_count,
        "updated_count" => imported_results.updated_count,
        "skipped_count" => imported_results.skipped_count,
        "error_count" => imported_results.failed_count
      }
      run.update!(business_metrics_imported_count: imported_results.size)
      if imported_results.failed_count.to_i.positive? || imported_results.skipped_count.to_i.positive?
        partial_failures << "business_metrics_import_partial"
        finish_step!(
          step,
          metadata: metadata.merge(
            warning: true,
            reason: "business_metrics_import_partial",
            message: "BusinessMetricDaily importは完了しましたが、一部Businessで失敗またはtimeoutしました。"
          )
        )
      else
        finish_step!(step, metadata:)
      end
      log!(
        "business_metrics_import finish processed=#{metadata['processed_business_count'].to_i} " \
        "created=#{metadata['created_count'].to_i} updated=#{metadata['updated_count'].to_i} " \
        "skipped=#{metadata['skipped_count'].to_i} errors=#{metadata['error_count'].to_i}"
      )
      imported_results
    end
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    Rails.logger.error("AICOO Daily Run business metrics import failed: #{error_message}")
    partial_failures << "business_metrics_import_failed"
    fail_step!(
      step,
      error_message,
      metadata: {
        error_class: e.class.name,
        backtrace: e.backtrace.to_a.first(5),
        message: "BusinessMetricDaily import failed and Daily Run continues as partial_failed."
      }
    ) if step
    log!("business_metrics_import failed: #{error_message}")
    []
  end

  def business_metrics_progress_callback(step)
    lambda do |progress|
      processed = progress.processed_business_count.to_i
      batch = progress_batch_for(processed)
      return unless progress_checkpoint?(step, batch:, processed:, event: progress.event)

      record_step_progress!(step, batch:, processed:)
      log!("business_metrics_import progress batch=#{batch} processed=#{processed} rss_mb=#{memory_snapshot['rss_mb'] || '-'}")
    end
  end

  def daily_step_progress_callback(step)
    lambda do |batch:, processed:, **attributes|
      return unless attributes[:insight_generation_progress].present? || progress_checkpoint?(step, batch:, processed:)

      record_step_progress!(step, batch:, processed:, **attributes)
      log!("daily_step progress step=#{step.step_name} batch=#{batch} processed=#{processed} rss_mb=#{memory_snapshot['rss_mb'] || '-'}")
      release_step_references!(step, release_reason: "batch") if attributes[:insight_generation_progress].present?
    end
  end

  def unsupported_progress_keyword?(error)
    error.message.match?(/unknown keyword|wrong number of arguments/i)
  end

  def progress_batch_for(processed)
    return 0 if processed <= 0

    (processed.to_f / PROGRESS_BATCH_SIZE).ceil
  end

  def progress_checkpoint?(step, batch:, processed:, event: nil)
    return true if event.to_s.in?(%w[start finish failed timeout step_timeout error])

    metadata = step.metadata.to_h
    batch != metadata["last_progress_batch"].to_i || processed.zero?
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

  def run_suelog_database_steps!(run)
    business = suelog_business
    unless business
      step = start_step!(run, "suelog_database_health_check")
      skip_step!(
        step,
        metadata: {
          warning: true,
          reason: "suelog_business_not_found",
          message: "吸えログBusinessが見つからないため、吸えログDB連携をスキップしました。"
        }
      )
      generation_step = start_step!(run, "suelog_candidate_generation")
      skip_step!(
        generation_step,
        metadata: {
          warning: true,
          reason: "suelog_business_not_found",
          message: "吸えログBusinessが見つからないため、候補生成をスキップしました。"
        }
      )
      log!("Suelog DB skipped: business_not_found")
      return
    end

    health_step = start_step!(run, "suelog_database_health_check")
    record_step_progress!(health_step, batch: 0, processed: 0)
    health = Aicoo::ExternalSources::SuelogHealthCheck.call
    if health.success?
      finish_step!(health_step, metadata: health.diagnostics.merge("business_id" => business.id))
      log!("Suelog DB connected shops=#{health.shops_count} articles=#{health.articles_count} shop_clicks_30d=#{health.shop_clicks_count}")
    else
      skip_step!(
        health_step,
        metadata: health.diagnostics.merge(
          "business_id" => business.id,
          warning: true,
          reason: health.code,
          message: "吸えログDBへ接続できないため、吸えログ専用候補生成をスキップしました。"
        )
      )
      log!("Suelog DB skipped code=#{health.code}")
      generation_step = start_step!(run, "suelog_candidate_generation")
      skip_step!(
        generation_step,
        metadata: health.diagnostics.merge(
          "business_id" => business.id,
          warning: true,
          reason: health.code,
          message: "吸えログDB接続が利用できないため、候補生成をスキップしました。"
        )
      )
      return
    end

    generation_step = start_step!(run, "suelog_candidate_generation")
    record_step_progress!(generation_step, batch: 0, processed: 0)
    article_routing = Aicoo::ArticleAnalyzerRouting.call(business:)
    result = Aicoo::CandidateGenerators::SuelogGenerator.call(business:)
    if result.health&.success?
      finish_step!(
        generation_step,
        metadata: result.diagnostics.merge(
          "business_id" => business.id,
          "action_type_counts" => result.created.group_by(&:action_type).transform_values(&:size)
        ).merge(article_routing.daily_run_metadata)
      )
      log!("Suelog candidates created=#{result.created_count} skipped=#{result.skipped_count}")
    else
      skip_step!(
        generation_step,
        metadata: result.diagnostics.merge(
          "business_id" => business.id,
          warning: true,
          reason: result.health&.code || "suelog_candidate_generation_skipped",
          message: "吸えログ専用候補生成はスキップされました。"
        ).merge(article_routing.daily_run_metadata)
      )
      log!("Suelog candidates skipped reason=#{result.health&.code || result.skipped.first}")
    end
  rescue StandardError => e
    fail_step!(health_step, "#{e.class}: #{safe_suelog_error(e)}") if defined?(health_step) && health_step&.running?
    fail_step!(generation_step, "#{e.class}: #{safe_suelog_error(e)}") if defined?(generation_step) && generation_step&.running?
    log!("Suelog DB integration failed but Daily Run continues: #{e.class}")
  end

  def suelog_business
    @suelog_business ||= Business.real_businesses.find_each.find do |business|
      Aicoo::Suelog::SiteInsightsAdapter.target?(business)
    end
  end

  def safe_suelog_error(error)
    error.message.to_s.gsub(ENV["SUELOG_DATABASE_URL"].to_s, "[FILTERED]")
  end

  def run_article_opportunity_analysis!(run)
    step = start_step!(run, Aicoo::ArticleOpportunityDailyRun::STEP_NAME)
    started_at = Time.current
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.article_opportunity_analysis", context: daily_run_memory_context(run, step_name: Aicoo::ArticleOpportunityDailyRun::STEP_NAME, step_id: step.id)) do
      record_step_progress!(step, batch: 0, processed: 0)
      business = suelog_business
      unless business
        result = Aicoo::ArticleOpportunityDailyRun::Result.new(
          "skipped",
          nil,
          nil,
          nil,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          nil,
          nil,
          [ "suelog_business_not_found" ]
        )
        skip_step!(
          step,
          metadata: Aicoo::ArticleOpportunityDailyRun.metadata_for(result).merge(
            "started_at" => started_at.iso8601,
            "finished_at" => Time.current.iso8601,
            warning: true,
            reason: "suelog_business_not_found",
            message: "吸えログBusinessが見つからないため、ArticleOpportunityAnalysisをスキップしました。"
          )
        )
        return result
      end

      result = Aicoo::ArticleOpportunityDailyRun.call(daily_run: run, business:)
      metadata = Aicoo::ArticleOpportunityDailyRun.metadata_for(result).merge(
        "started_at" => started_at.iso8601,
        "finished_at" => Time.current.iso8601
      )
      case result.status
      when "skipped"
        skip_step!(
          step,
          metadata: metadata.merge(
            warning: true,
            reason: result.errors.first.presence || "article_opportunity_analysis_skipped",
            message: "ArticleOpportunityAnalysisは対象外または必要データ不足のためスキップされました。"
          )
        )
      when "failed"
        partial_failures << "article_opportunity_analysis_failed"
        fail_step!(
          step,
          result.errors.first.presence || "article_opportunity_analysis_failed",
          metadata: metadata.merge(
            reason: "article_opportunity_analysis_failed",
            message: "ArticleOpportunityAnalysisに失敗しました。Daily Runは可能な後続処理を継続します。"
          )
        )
      when "warning"
        finish_step!(
          step,
          metadata: metadata.merge(
            warning: true,
            reason: "article_opportunity_analysis_partial",
            message: "ArticleOpportunityAnalysisは完了しましたが、一部欠損・重複抑制・Today候補0件があります。"
          )
        )
      else
        finish_step!(step, metadata:)
      end
      result
    end
  rescue StandardError => e
    error_message = "#{e.class}: #{e.message}"
    partial_failures << "article_opportunity_analysis_failed"
    fail_step!(
      step,
      error_message,
      metadata: {
        error_class: e.class.name,
        backtrace: e.backtrace.to_a.first(5),
        message: "ArticleOpportunityAnalysis failed and Daily Run continues as partial_failed."
      }
    ) if step
    log!("ArticleOpportunityAnalysis failed: #{error_message}")
    Aicoo::ArticleOpportunityDailyRun::Result.new("failed", nil, nil, nil, 0, 0, 0, 0, 0, 0, 1, 0, nil, nil, [ error_message ])
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
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.action_generation", context: daily_run_memory_context(run, step_name: "action_generation", step_id: step.id)) do
      result = normalize_action_generation_result(call_metric_action_candidate_generator(step))
      generated_count = result.created_count
      skipped_reasons = result.skipped
      metadata = {
        created_count: generated_count,
        skipped_count: result.skipped_count,
        failed_count: result.failed_count,
        result_count: result.created_count.to_i + result.skipped_count.to_i + result.failed_count.to_i,
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
      result
    end
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def call_metric_action_candidate_generator(step)
    MetricActionCandidateGenerator.generate_all!(progress: daily_step_progress_callback(step))
  rescue ArgumentError => e
    raise unless unsupported_progress_keyword?(e)

    MetricActionCandidateGenerator.generate_all!
  end

  def normalize_action_generation_result(result)
    return result unless result.is_a?(Array)

    result.reduce(MetricActionCandidateGenerator::Result.new) { |summary, item| summary + item }
  end

  def action_generation_zero_message(skipped_reasons)
    return "ActionCandidate Generatorは実行されましたが、生成対象Businessがないか、生成条件に一致しませんでした。" if skipped_reasons.blank?

    "ActionCandidate Generatorは実行されましたが0件でした。理由: #{skipped_reasons.first(5).join(' / ')}"
  end

  def run_insight_generation!(run)
    step = start_step!(run, "insight_generation")
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.insight_generation", context: daily_run_memory_context(run, step_name: "insight_generation", step_id: step.id)) do
      result = call_insight_generator(step)
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
    end
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def call_insight_generator(step)
    AicooInsight::Generator.generate_all!(
      source: "daily_run",
      progress: daily_step_progress_callback(step),
      memory_context: daily_run_memory_context(step.aicoo_daily_run, step_name: "insight_generation", step_id: step.id)
    )
  rescue ArgumentError => e
    raise unless unsupported_progress_keyword?(e)

    AicooInsight::Generator.generate_all!(source: "daily_run")
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
        "codex_issue_processed_count",
        "codex_issue_created_count",
        "codex_issue_skipped_count",
        "codex_issue_failed_count",
        "codex_issue_details",
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
    trigger_result = Aicoo::ActivityEvaluationTrigger.call(invoked_by: "DailyRun")
    result = trigger_result.builder_result
    raise trigger_result.exception if result.nil? && trigger_result.exception.present?

    action_results_generated_count = result.action_results_generated_count.to_i
    finish_step!(
      step,
      metadata: {
        created_count: result.created_count,
        evaluated_count: result.evaluated_count,
        skipped_count: result.skipped_count,
        pending_count: result.pending_count,
        failed_count: result.failed_count.to_i,
        builder_should_run_count: trigger_result.builder_should_run_count,
        builder_invoked_count: trigger_result.builder_invoked_count,
        builder_completed_count: trigger_result.builder_completed_count,
        builder_failed_count: trigger_result.builder_failed_count,
        action_results_generated_count:
      }
    )
    log!(
      "ActivityEvaluation created=#{result.created_count} evaluated=#{result.evaluated_count} " \
      "skipped=#{result.skipped_count} pending=#{result.pending_count} failed=#{result.failed_count.to_i} " \
      "builder_invoked=#{trigger_result.builder_invoked_count} " \
      "builder_completed=#{trigger_result.builder_completed_count} " \
      "action_results_generated=#{action_results_generated_count}"
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
    line = "[#{Time.current.iso8601}] #{message.to_s.squish.truncate(MAX_RUN_LOG_LINE_LENGTH)}"
    log_lines << line
    log_lines.shift while log_lines.size > MAX_RUN_LOG_LINES
  end

  def log_text
    log_lines.join("\n")
  end

  def record_step!(run, step_name)
    step = start_step!(run, step_name)
    Aicoo::MemoryDiagnostics.measure("AicooDailyRunner.step.#{step_name}", context: daily_run_memory_context(run, step_name:, step_id: step.id)) do
      record_step_progress!(step, batch: 0, processed: 0)
      result = yield
      finish_step!(step)
      result
    end
  rescue StandardError => e
    fail_step!(step, "#{e.class}: #{e.message}") if step
    raise
  end

  def start_step!(run, step_name)
    run.aicoo_daily_run_steps.create!(
      step_name:,
      status: "running",
      started_at: Time.current,
      metadata: initial_step_memory_metadata
    )
  end

  def finish_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "success",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: step_metadata_with_memory_event(step, "finish", metadata)
    )
  ensure
    release_step_references!(step, release_reason: "finish")
  end

  def fail_step!(step, error_message, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "failed",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      error_message:,
      metadata: step_metadata_with_memory_event(step, "error", metadata)
    )
  ensure
    release_step_references!(step, release_reason: "error")
  end

  def skip_step!(step, metadata: {})
    finished_at = Time.current
    step.update!(
      status: "skipped",
      finished_at:,
      duration_seconds: step_duration(step, finished_at),
      metadata: step_metadata_with_memory_event(step, "skipped", metadata)
    )
  ensure
    release_step_references!(step, release_reason: "skipped")
  end

  def release_step_references!(step_or_run, step_name = nil, release_reason: "manual")
    step = if step_name
      step_or_run.aicoo_daily_run_steps.where(step_name:).recent.first
    else
      step_or_run
    end
    unless step
      Rails.logger.warn("[MemoryDiagnostics] release skipped reason=step_not_found step_name=#{step_name || '-'}")
      return
    end

    Aicoo::MemoryDiagnostics.point(
      "DailyRun::release_step_references.entry",
      context: daily_run_memory_context(step.aicoo_daily_run, step_name: step.step_name, step_id: step.id).merge(release_reason:)
    )

    before_gc = memory_event("gc_before")
    clear_step_runtime_references!
    compact_memory!
    after_gc = memory_event("gc_after")
    metadata = step.metadata.to_h
    metadata = append_memory_event(metadata, before_gc)
    metadata = append_memory_event(metadata, after_gc)
    gc_delta = memory_event_delta_mb(before_gc, after_gc)
    metadata = {
      "memory_gc_before" => before_gc,
      "memory_gc_after" => after_gc,
      "memory_gc_delta_mb" => gc_delta
    }.compact.merge(metadata)
    save_release_metadata!(step, metadata)
    message =
      "Step memory released step=#{step.step_name} " \
      "gc_before_rss_mb=#{before_gc['rss_mb'] || '-'} " \
      "gc_after_rss_mb=#{after_gc['rss_mb'] || '-'} " \
      "gc_delta_mb=#{gc_delta || '-'}"
    Rails.logger.info(message)
    log!(message)
  rescue StandardError => e
    Rails.logger.warn("[MemoryDiagnostics] release metadata save failed step_id=#{step&.id || '-'} error_class=#{e.class} error_message=#{e.message}")
  end

  def save_release_metadata!(step, metadata)
    step.update_columns(metadata: sanitize_metadata(metadata), updated_at: Time.current)
  end

  def clear_step_runtime_references!
    ActiveRecord::Base.clear_query_caches_for_current_thread if ActiveRecord::Base.respond_to?(:clear_query_caches_for_current_thread)
    ActiveRecord::Base.connection.clear_query_cache if ActiveRecord::Base.connected?
  rescue StandardError => e
    Rails.logger.debug("AICOO Daily Run query cache clear skipped: #{e.class}: #{e.message}")
  end

  def step_duration(step, finished_at)
    return unless step.started_at

    finished_at - step.started_at
  end

  def initial_step_memory_metadata
    start_event = memory_event("start", batch: 0, processed: 0)
    {
      "heartbeat" => start_event["at"],
      "memory_start" => start_event,
      "last_memory_event" => start_event,
      "memory_events" => [ start_event ]
    }
  end

  def record_step_progress!(step, batch:, processed:, **attributes)
    event = memory_event("progress", batch:, processed:)
    metadata = append_memory_event(step.metadata.to_h, event)
    metadata["heartbeat"] = event["at"]
    metadata["last_progress"] = event
    metadata["last_progress_batch"] = event["batch"]
    metadata["last_progress_processed"] = event["processed"]
    metadata["insight_generation_progress"] = sanitize_metadata(attributes[:insight_generation_progress].deep_stringify_keys) if attributes[:insight_generation_progress].present?
    step.update_columns(metadata:, updated_at: Time.current)
  end

  def step_metadata_with_memory_event(step, event_name, metadata)
    event = memory_event(event_name)
    merged = step.metadata.to_h.merge(sanitize_metadata(metadata.deep_stringify_keys))
    merged = ensure_progress_event(merged)
    merged = append_memory_event(merged, event)
    merged["heartbeat"] = event["at"]
    merged["memory_finish"] = event if event_name.in?(%w[finish error skipped])
    memory_delta = memory_delta_mb(merged)
    merged["memory_delta_mb"] = memory_delta if memory_delta
    sanitize_metadata(merged)
  end

  def append_memory_event(metadata, event)
    events = Array(metadata["memory_events"]).last(MAX_STEP_MEMORY_EVENTS - 1)
    metadata.merge(
      "last_memory_event" => event,
      "memory_events" => events + [ event ]
    )
  end

  def ensure_progress_event(metadata)
    events = Array(metadata["memory_events"])
    return metadata if events.any? { |event| event.is_a?(Hash) && event["event"] == "progress" }

    append_memory_event(metadata, memory_event("progress", batch: 0, processed: 0))
  end

  def memory_event(event_name, batch: nil, processed: nil)
    memory_snapshot.merge(
      "event" => event_name,
      "at" => Time.current.iso8601,
      "batch" => batch,
      "processed" => processed
    ).compact
  end

  def sanitize_metadata(value)
    case value
    when Hash
      value.first(MAX_METADATA_HASH_KEYS).to_h do |key, item|
        [ key.to_s, sanitize_metadata(item) ]
      end
    when Array
      value.first(MAX_METADATA_ARRAY_ITEMS).map { |item| sanitize_metadata(item) }
    when String
      value.truncate(MAX_METADATA_STRING_LENGTH)
    else
      value
    end
  end

  def memory_delta_mb(metadata)
    start_mb = metadata.dig("memory_start", "rss_mb")
    finish_mb = metadata.dig("memory_finish", "rss_mb")
    return if start_mb.blank? || finish_mb.blank?

    (finish_mb.to_d - start_mb.to_d).round(1).to_s
  end

  def memory_event_delta_mb(before_event, after_event)
    before_mb = before_event["rss_mb"]
    after_mb = after_event["rss_mb"]
    return if before_mb.blank? || after_mb.blank?

    (after_mb.to_d - before_mb.to_d).round(1).to_s
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
    Aicoo::MemoryDiagnostics.current_rss_mb&.*(1024)&.to_i || linux_rss_kb || ps_rss_kb
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

  def daily_run_memory_context(run = nil, extra = {})
    {
      daily_run_id: run&.id,
      target_date: target_date.to_s,
      source:
    }.merge(extra).compact
  end

  def retry_count_for_today
    AicooDailyRun.where(target_date:).where.not(status: %w[skipped duplicate_skipped]).count
  end
end

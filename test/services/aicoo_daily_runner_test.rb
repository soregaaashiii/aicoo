require "test_helper"
require "stringio"

class AicooDailyRunnerTest < ActiveSupport::TestCase
  setup do
    AicooAutoRevisionSetting.delete_all
    AutoRevisionQueueRun.delete_all
    AutoRevisionTask.delete_all
    ActionCandidate.update_all(status: "done")
    DataSourceCostProfile.ensure_defaults!
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: nil)
  end

  test "successful run marks daily run as succeeded and stores counts" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [ Object.new, Object.new ], skipped: [])

    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: [ Object.new ]) do
      run = AicooDailyRunner.run!(target_date:)

      assert_equal "success", run.status
      assert_equal target_date, run.target_date
      assert_equal "manual", run.source
      assert_equal 0, run.retry_count
      assert_equal 1, run.analytics_fetch_count
      assert_equal 4, run.snapshot_count
      assert_equal 1, run.insight_generated_count
      assert_equal 2, run.business_metrics_imported_count
      assert_equal 1, run.proxy_weights_adjusted_count
      assert_equal 2, run.action_candidates_generated_count
      assert_equal 1, run.action_results_evaluated_count
      assert_equal 3, run.score_snapshots_created_count
      assert_equal 1, run.score_snapshot_rank_up_count
      assert_equal 1, run.score_snapshot_rank_down_count
      assert_equal 1, run.score_snapshot_no_adjustment_count
      assert_equal 5, run.data_preparation_candidates_count
      assert_equal 3, run.data_preparation_auto_queued_count
      assert_equal true, run.calibration_ran
      assert_equal 2, run.updated_calibration_count
      assert_equal 2, run.calibration_log_count
      assert_equal 0, run.pending_calibration_count
      assert_match "Daily Run finished", run.run_log
      assert_match "Analytics fetched success=1 failed=0", run.run_log
      assert_match "DataHub collected snapshots count=4", run.run_log
      assert_match "Insight generated count=1", run.run_log
      assert_match "Insight skipped count=2", run.run_log
      assert_match "Explore Opportunity generated count=0", run.run_log
      assert_match "ActionCandidate score snapshots created count=3", run.run_log
      assert_match "Data preparation candidates: 5", run.run_log
      assert_match "Auto queued: 3", run.run_log
      assert_match "Skipped: 2", run.run_log
      assert_match "Reason: already queued=2", run.run_log
      assert_match "MetaEvaluationSnapshot created count=5", run.run_log
      assert_match "Most trusted evaluator: gsc", run.run_log
      assert_match "GSC average confidence=82.0", run.run_log
      assert_match "Calibration finished updated_calibration_count=2", run.run_log
      assert_match "pending_calibration_count=0", run.run_log
      assert_match "OwnerExecutionQueue created count=2", run.run_log
      assert_match "AnalysisCandidate created count=1", run.run_log
      assert_match "AutoRevisionQueue generated=0 skipped=0 high_risk=0", run.run_log
      assert_match "PipelineStuckDetector checked=", run.run_log
      assert_match "BusinessPlaybook updated count=2", run.run_log
      assert_no_match "SERP optional mode", run.run_log
      assert_equal 23, run.aicoo_daily_run_steps.count
      assert_equal %w[
        analytics_fetch
        datahub_collect
        business_metrics_import
        activity_log_evaluation_queue_build
        source_app_diff_detection
        proxy_weight_adjustment
        action_generation
        insight_generation
        explore_opportunity_generation
        action_result_evaluation
        score_snapshot
        data_preparation_queue
        meta_evaluation_snapshot
        calibration
        owner_task_digest
        owner_execution_queue
        analysis_orchestration
        business_playbook_update
        traffic_channel_recording
        system_mode_snapshot
        resource_aware_auto_build
        auto_revision_queue
        pipeline_stuck_detection
      ], run.aicoo_daily_run_steps.order(:created_at).pluck(:step_name)
      assert_equal %w[skipped success], run.aicoo_daily_run_steps.distinct.pluck(:status).sort
      assert_equal %w[
        resource_aware_auto_build
      ].sort, run.aicoo_daily_run_steps.skipped.pluck(:step_name).sort
      assert_equal "success", run.status
      assert_equal 1, AutoRevisionQueueRun.count
      assert_equal %i[analytics datahub import activity_eval source_diff adjust_all generate insight evaluate snapshot queue meta_snapshot calibration owner_queue analysis playbook traffic_channel], order
    end
  end

  test "successful run queues auto revision tasks when enabled" do
    AicooAutoRevisionSetting.current.update!(enabled: true, max_tasks_per_run: 1)
    create_auto_revision_candidate
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: []) do
      run = AicooDailyRunner.run!(target_date:)

      assert_equal "success", run.status
      assert_equal 1, AutoRevisionQueueRun.count
      assert_equal 1, AutoRevisionTask.count
      assert_equal run, AutoRevisionQueueRun.last.aicoo_daily_run
      assert_match "AutoRevisionQueue generated=1", run.run_log
    end
  end

  test "does not run serp fetch inside daily run when api key is configured" do
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "configured")
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])
    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: []) do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_nil run.aicoo_daily_run_steps.find_by(step_name: "serp_fetch")
      assert_no_match "SERP fetched", run.run_log
      assert_not_includes order, :serp
    end
  end

  test "analytics auth failures are treated as non blocking warnings" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(
      order:,
      adjuster:,
      generator_results: [ generator_result ],
      evaluated_results: [],
      analytics_status: "failed",
      analytics_error_message: "Google OAuth error: invalid_grant Token has been expired or revoked."
    ) do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_equal "success", run.status
      assert_equal "cron", run.source
      assert_equal 0, run.analytics_fetch_count
      assert_match "Analytics fetched success=0 failed=1", run.run_log
      analytics_step = run.aicoo_daily_run_steps.find_by!(step_name: "analytics_fetch")
      assert_equal "skipped", analytics_step.status
      assert_nil analytics_step.error_message
      assert_equal true, analytics_step.metadata.fetch("warning")
      assert_equal "analytics_optional_unavailable", analytics_step.metadata.fetch("reason")
    end
  end

  test "stores action generation zero reasons in step metadata" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(
      created: [],
      skipped: [ "吸えログ: 改善候補生成条件に一致しません / metric_days=30 / recent7_clicks=0" ]
    )

    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: []) do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_equal "success", run.status
      assert_equal 0, run.action_candidates_generated_count
      assert_match "ActionCandidate skipped reasons=吸えログ", run.run_log
      step = run.aicoo_daily_run_steps.find_by!(step_name: "action_generation")
      assert_equal "success", step.status
      assert_equal true, step.metadata.fetch("warning")
      assert_equal "no_action_candidates_generated", step.metadata.fetch("reason")
      assert_includes step.metadata.fetch("message"), "0件"
      assert_includes step.metadata.fetch("skipped_reasons").first, "recent7_clicks=0"
    end
  end

  test "stores insight generation zero reasons in step metadata" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [ Object.new ], skipped: [])
    insight_result = AicooInsight::Generator::Result.new(
      created: [],
      skipped: [ "吸えログ: Insight生成条件に一致しません / gsc_rows=0" ]
    )

    stub_daily_steps(
      order:,
      adjuster:,
      generator_results: [ generator_result ],
      evaluated_results: [],
      insight_result:
    ) do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_equal "success", run.status
      assert_equal 0, run.insight_generated_count
      step = run.aicoo_daily_run_steps.find_by!(step_name: "insight_generation")
      assert_equal "success", step.status
      assert_equal true, step.metadata.fetch("warning")
      assert_equal "no_insights_generated", step.metadata.fetch("reason")
      assert_includes step.metadata.fetch("message"), "0件"
      assert_includes step.metadata.fetch("skipped_reasons").first, "gsc_rows=0"
    end
  end

  test "stores memory samples in daily run step metadata" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [ Object.new ], skipped: [])

    with_method_stub(AicooDailyRunner, :current_rss_kb, -> { 128 * 1024 }) do
      stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: []) do
        run = AicooDailyRunner.run!(target_date:, source: "cron")
        step = run.aicoo_daily_run_steps.find_by!(step_name: "action_generation")

        assert_equal "128.0", step.metadata.dig("memory_start", "rss_mb")
        assert_equal "128.0", step.metadata.dig("memory_finish", "rss_mb")
        assert_equal "0.0", step.metadata.fetch("memory_delta_mb")
        assert_equal "128.0", step.metadata.dig("memory_gc_before", "rss_mb")
        assert_equal "128.0", step.metadata.dig("memory_gc_after", "rss_mb")
        assert_equal "0.0", step.metadata.fetch("memory_gc_delta_mb")
      end
    end
  end

  test "stores business and candidate progress only at batch checkpoints" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 7, 23), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")
    step = runner.send(:start_step!, run, "action_generation")
    callback = runner.send(:daily_step_progress_callback, step)

    callback.call(
      batch: 1,
      processed: 25,
      current_business_id: businesses(:suelog).id,
      current_business_name: businesses(:suelog).name,
      current_business_index: 25,
      total_business_count: 100,
      current_candidate_count: 40,
      total_candidate_count: 160
    )
    first_checkpoint = step.reload.metadata

    callback.call(
      batch: 1,
      processed: 26,
      current_business_index: 26,
      total_business_count: 100,
      current_candidate_count: 41,
      total_candidate_count: 158
    )
    second_checkpoint = step.reload.metadata

    assert_equal 25, first_checkpoint.fetch("last_progress_processed")
    assert_equal first_checkpoint, second_checkpoint
    assert_equal businesses(:suelog).name, first_checkpoint.fetch("current_business_name")
    assert_equal 40, first_checkpoint.fetch("current_candidate_count")
    assert_equal 160, first_checkpoint.fetch("total_candidate_count")
  end

  test "stores weighted progress and the applicable step plan in existing step metadata" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 7, 23), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")
    runner.instance_variable_set(:@daily_run_progress_step_names, %w[action_generation])
    runner.instance_variable_set(:@daily_run_progress_averages, { "action_generation" => 400.0 })
    runner.instance_variable_set(:@daily_run_progress_steps, [])
    runner.instance_variable_set(:@daily_run_progress_percent, 0)
    step = runner.send(:start_step!, run, "action_generation")

    runner.send(
      :record_step_progress!,
      step,
      batch: 1,
      processed: 25,
      current_business_index: 25,
      total_business_count: 100
    )

    metadata = step.reload.metadata
    assert_equal 25, metadata.fetch("progress_percent")
    assert_equal true, metadata.dig("progress_step_plan", "action_generation")
    assert_equal false, metadata.dig("progress_step_plan", "analytics_fetch")
  end

  test "marks a configuration-disabled skipped step as excluded from progress" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 7, 23), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")
    step = runner.send(:start_step!, run, "auto_revision_queue")

    runner.send(:skip_step!, step, metadata: { reason: "disabled" })

    assert_equal false, step.reload.metadata.fetch("progress_applicable")
  end

  test "persists nondecreasing weighted progress when a step finishes" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 7, 23), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")
    runner.instance_variable_set(:@daily_run_progress_step_names, %w[analytics_fetch insight_generation])
    runner.instance_variable_set(
      :@daily_run_progress_averages,
      { "analytics_fetch" => 100.0, "insight_generation" => 300.0 }
    )
    runner.instance_variable_set(:@daily_run_progress_steps, [])
    runner.instance_variable_set(:@daily_run_progress_percent, 0)
    step = runner.send(:start_step!, run, "analytics_fetch")

    runner.send(:finish_step!, step)

    assert_equal 25, step.reload.metadata.fetch("progress_percent")
  end

  test "releases memory metadata for success skipped and failed steps" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")

    with_method_stub(AicooDailyRunner, :current_rss_kb, -> { 128 * 1024 }) do
      success_step = runner.send(:start_step!, run, "success_step")
      skip_step = runner.send(:start_step!, run, "skip_step")
      failed_step = runner.send(:start_step!, run, "failed_step")

      runner.send(:finish_step!, success_step, metadata: { keep: "yes" })
      runner.send(:skip_step!, skip_step, metadata: { keep: "yes" })
      runner.send(:fail_step!, failed_step, "boom", metadata: { keep: "yes" })

      [ success_step, skip_step, failed_step ].each do |step|
        step.reload
        assert_equal "128.0", step.metadata.dig("memory_gc_before", "rss_mb")
        assert_equal "128.0", step.metadata.dig("memory_gc_after", "rss_mb")
        assert_equal "0.0", step.metadata.fetch("memory_gc_delta_mb")
        assert_equal "yes", step.metadata.fetch("keep")
      end
    end
  end

  test "record step releases memory even when step body raises original exception" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")

    with_method_stub(AicooDailyRunner, :current_rss_kb, -> { 128 * 1024 }) do
      error = assert_raises(RuntimeError) do
        runner.send(:record_step!, run, "raise_step") { raise "original boom" }
      end

      assert_equal "original boom", error.message
      step = run.aicoo_daily_run_steps.find_by!(step_name: "raise_step")
      assert_equal "failed", step.status
      assert_equal "128.0", step.metadata.dig("memory_gc_before", "rss_mb")
      assert_equal "128.0", step.metadata.dig("memory_gc_after", "rss_mb")
    end
  end

  test "release memory warns when step cannot be found" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")

    output = capture_rails_logger do
      runner.send(:release_step_references!, run, "missing_step")
    end

    assert_includes output, "release skipped reason=step_not_found"
  end

  test "release memory warns when metadata save fails" do
    run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "running", source: "manual")
    runner = AicooDailyRunner.new(target_date: run.target_date, source: "manual")
    step = runner.send(:start_step!, run, "save_fail_step")

    output = capture_rails_logger do
      with_method_stub(AicooDailyRunner, :save_release_metadata!, ->(_step, _metadata) { raise "save failed" }) do
        runner.send(:release_step_references!, step)
      end
    end

    assert_includes output, "release metadata save failed"
  end

  test "unknown analytics failures still mark daily run as partial failed" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(
      order:,
      adjuster:,
      generator_results: [ generator_result ],
      evaluated_results: [],
      analytics_status: "failed",
      analytics_error_message: "Unexpected parser failure"
    ) do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_equal "partial_failed", run.status
      analytics_step = run.aicoo_daily_run_steps.find_by!(step_name: "analytics_fetch")
      assert_equal "failed", analytics_step.status
      assert_match "analytics_failed=1", analytics_step.error_message
    end
  end

  test "calibration failure does not crash daily run" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(
      order:,
      adjuster:,
      generator_results: [ generator_result ],
      evaluated_results: [],
      calibration_error: RuntimeError.new("calibration boom")
    ) do
      run = AicooDailyRunner.run!(target_date:)

      assert_equal "partial_failed", run.status
      assert_equal false, run.calibration_ran
      assert_match "RuntimeError: calibration boom", run.calibration_error
      assert_match "Calibration failed", run.run_log
      calibration_step = run.aicoo_daily_run_steps.find_by!(step_name: "calibration")
      assert_equal "failed", calibration_step.status
      assert_match "RuntimeError: calibration boom", calibration_step.error_message
    end
  end

  test "business metric import failure stores failed step and lets run continue as partial failed" do
    error = RuntimeError.new("boom")
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(
      order:,
      adjuster:,
      generator_results: [ generator_result ],
      evaluated_results: [],
      business_metric_error: error
    ) do
      run = AicooDailyRunner.run!(target_date:)

      assert_equal "partial_failed", run.status
      assert_match "business_metrics_import_failed", run.run_log
      step = run.aicoo_daily_run_steps.find_by!(step_name: "business_metrics_import")
      assert_equal "failed", step.status
      assert_match "RuntimeError: boom", step.error_message
    end
  end

  test "records duplicate skipped when daily run is already running for same target date" do
    target_date = Date.new(2026, 6, 21)
    existing = AicooDailyRun.create!(target_date:, status: "running", started_at: Time.current)

    with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:, progress: nil) { raise "should not be called" }) do
      run = AicooDailyRunner.run!(target_date:)

      assert_equal "duplicate_skipped", run.status
      assert_equal target_date, run.target_date
      assert_match "already_running", run.run_log
      assert_match "existing_run_id=#{existing.id}", run.run_log
    end
  end

  test "repairs orphan running run and allows manual rerun for same target date" do
    target_date = Date.new(2026, 6, 21)
    orphan = AicooDailyRun.create!(target_date:, status: "running", source: "cron", started_at: 1.hour.ago, updated_at: 1.hour.ago)
    orphan.aicoo_daily_run_steps.create!(
      step_name: "insight_generation",
      status: "running",
      started_at: 55.minutes.ago,
      metadata: { "heartbeat" => 55.minutes.ago.iso8601 }
    )
    orphan.current_step.update_columns(updated_at: 55.minutes.ago)
    orphan.update_columns(updated_at: 1.hour.ago)
    order = []
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: []) do
      run = AicooDailyRunner.run!(target_date:, source: "manual")

      assert_equal "stuck", orphan.reload.status
      assert orphan.finished_at.present?
      assert_equal "failed", orphan.current_step.status
      assert_equal "success", run.status
      assert_equal "manual", run.source
      assert_not_equal orphan.id, run.id
    end
  end

  test "records duplicate skipped when advisory lock is not acquired" do
    target_date = Date.new(2026, 6, 21)

    with_method_stub(AicooDailyRunner, :acquire_daily_run_lock, -> { false }) do
      with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:, progress: nil) { raise "should not be called" }) do
        run = AicooDailyRunner.run!(target_date:, source: "manual")

        assert_equal "duplicate_skipped", run.status
        assert_equal target_date, run.target_date
        assert_equal "manual", run.source
        assert_match "daily_run_lock_not_acquired", run.run_log
      end
    end
  end

  private

  def fake_adjuster(order)
    Object.new.tap do |adjuster|
      adjuster.define_singleton_method(:adjust_all_businesses!) do |start_date:, end_date:|
        order << :adjust_all
        [ Object.new ]
      end
      adjuster.define_singleton_method(:adjust_global!) do |start_date:, end_date:|
        order << :adjust_global
        Object.new
      end
    end
  end

  def create_auto_revision_candidate
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SEOタイトル改善 自動投入",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt: "SEOタイトルを改善してください。"
    )
  end

  def stub_daily_steps(
    order:,
    adjuster:,
    generator_results:,
    evaluated_results:,
    analytics_status: "success",
    analytics_error_message: nil,
    calibration_error: nil,
    business_metric_error: nil,
    insight_result: nil
  )
    with_singleton_stub(AicooAnalytics::DailyFetchJob, :perform_now, -> {
      fake_analytics_fetch(order, analytics_status, analytics_error_message)
    }) do
      with_singleton_stub(AicooDataHub::DailyCollector, :new, -> { fake_datahub_collector(order) }) do
        with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:, progress: nil) {
          order << :import
          raise business_metric_error if business_metric_error

          progress&.call(BusinessMetricDailyImporter::Progress.new(
            event: "finish",
            target_business_count: 2,
            processed_business_count: 2,
            current_business_id: nil,
            current_business_name: nil,
            created_count: 1,
            updated_count: 1,
            skipped_count: 0,
            error_count: 0,
            elapsed_seconds: 1,
            last_progress_at: Time.current,
            error_message: nil
          ))
          [ Object.new, Object.new ]
        }) do
          with_singleton_stub(Aicoo::SourceAppDiffDetector, :new, -> { fake_source_app_diff_detector(order) }) do
            with_singleton_stub(ProxyScoreWeightAdjuster, :new, -> { adjuster }) do
              with_singleton_stub(MetricActionCandidateGenerator, :generate_all!, -> {
                order << :generate
                generator_results
              }) do
                with_singleton_stub(AicooInsight::Generator, :generate_all!, ->(source:) {
                  order << :insight
                  insight_result || AicooInsight::Generator::Result.new(created: [ Object.new ], skipped: [ Object.new, Object.new ])
                }) do
                  with_singleton_stub(ActionResultEvaluator, :evaluate_pending!, -> {
                    order << :evaluate
                    evaluated_results
                  }) do
                    with_singleton_stub(Aicoo::ActivityEvaluationBuilder, :new, -> { fake_activity_evaluation_builder(order) }) do
                      with_method_stub(ActionCandidateScoreSnapshotter, :snapshot_top_candidates!, ->(date:) {
                        order << :snapshot
                        ActionCandidateScoreSnapshotter::Result.new(
                          snapshots: [ Object.new, Object.new, Object.new ],
                          created_count: 3,
                          rank_up_count: 1,
                          rank_down_count: 1,
                          no_adjustment_count: 1
                        )
                      }) do
                        with_singleton_stub(DataPreparationExecutorQueuer, :new, -> { fake_queuer(order) }) do
                          with_singleton_stub(MetaEvaluationSnapshotter, :new, -> { fake_meta_snapshotter(order) }) do
                            with_singleton_stub(Aicoo::CalibrationEngine, :run!, ->(source:, aicoo_daily_run:) {
                              order << :calibration
                              raise calibration_error if calibration_error

                              Aicoo::CalibrationEngine::Result.new(
                                calibrations: [ Object.new, Object.new ],
                                logs: [ Object.new, Object.new ]
                              )
                            }) do
                              with_singleton_stub(Aicoo::OwnerExecutionQueueBuilder, :new, ->(due_on:, generated_from:) {
                                fake_owner_execution_queue_builder(order)
                              }) do
                                with_singleton_stub(Aicoo::AnalysisOrchestrator, :run_all!, ->(today:, limit_per_business:, collect_records: true) {
                                  order << :analysis
                                  Aicoo::AnalysisOrchestrator::Result.new(
                                    generated_at: Time.current,
                                    candidates: [ Object.new ],
                                    created_count: 1,
                                    updated_count: 2,
                                    skipped_count: 3
                                  )
                                }) do
                                  with_singleton_stub(Aicoo::BusinessPlaybookBuilder, :update_all!, ->(collect_records: true) {
                                    order << :playbook
                                    Aicoo::BusinessPlaybookBuilder::Result.new(
                                      updated_count: 2,
                                      playbooks: [ Object.new, Object.new ]
                                    )
                                  }) do
                                    with_singleton_stub(Aicoo::Serp::PriorityUpdater, :update_all!, -> {
                                      order << :serp_learning
                                      Aicoo::Serp::PriorityUpdater::Result.new(
                                        updated_count: 1,
                                        suggested_count: 2,
                                        inactive_candidate_count: 0,
                                        skipped_count: 0
                                      )
                                    }) do
                                      with_singleton_stub(Aicoo::TrafficChannels::DailyRecorder, :record!, ->(daily_run:) {
                                        order << :traffic_channel
                                        Aicoo::TrafficChannels::DailyRecorder::Result.new(recorded_count: 1, skipped_count: 7)
                                      }) do
                                        yield
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def fake_analytics_fetch(order, status, error_message = nil)
    order << :analytics
    setting = AnalyticsSourceSetting.create!(
      name: "Daily runner test #{status} #{SecureRandom.hex(4)}",
      source_type: "gsc",
      site_url: "sc-domain:#{SecureRandom.hex(8)}.test",
      enabled: false
    )
    setting.analytics_fetch_runs.create!(
      status:,
      started_at: Time.current,
      finished_at: Time.current,
      error_message:
    )
  end

  def fake_datahub_collector(order)
    Object.new.tap do |collector|
      collector.define_singleton_method(:call) do
        order << :datahub
        AicooDataHubCollectionRun.new(status: "success", started_at: Time.current, finished_at: Time.current, snapshot_count: 4)
      end
    end
  end

  def fake_queuer(order)
    Object.new.tap do |queuer|
      queuer.define_singleton_method(:call) do
        order << :queue
        DataPreparationExecutorQueuer::Result.new(
          candidate_count: 5,
          queued_count: 3,
          skipped_count: 2,
          skipped_reasons: { "already queued" => 2 },
          disabled: false
        )
      end
    end
  end

  def fake_source_app_diff_detector(order)
    Object.new.tap do |detector|
      detector.define_singleton_method(:call) do
        order << :source_diff
        Aicoo::SourceAppDiffDetector::Result.new(created_count: 1, skipped_count: 0, error_count: 0)
      end
    end
  end

  def fake_serp_scan_runner(order, result)
    Object.new.tap do |runner|
      runner.define_singleton_method(:call) do
        order << :serp
        result
      end
    end
  end

  def fake_activity_evaluation_builder(order)
    Object.new.tap do |builder|
      builder.define_singleton_method(:call) do
        order << :activity_eval
        Aicoo::ActivityEvaluationBuilder::Result.new(
          created_count: 1,
          evaluated_count: 1,
          skipped_count: 0,
          pending_count: 0
        )
      end
    end
  end

  def fake_meta_snapshotter(order)
    Object.new.tap do |snapshotter|
      snapshotter.define_singleton_method(:snapshot!) do |date:, aicoo_daily_run:|
        order << :meta_snapshot
        MetaEvaluationSnapshotter::Result.new(
          snapshots: Array.new(5),
          created_count: 5,
          top_evaluator: "gsc",
          confidence_by_type: {
            "gsc" => 82.to_d,
            "ga4" => 72.to_d,
            "judge" => 15.to_d,
            "revenue" => 0.to_d,
            "learning" => 40.to_d
          }
        )
      end
    end
  end

  def fake_owner_execution_queue_builder(order)
    Object.new.tap do |builder|
      builder.define_singleton_method(:call) do
        order << :owner_queue
        Aicoo::OwnerExecutionQueueBuilder::Result.new(
          created: [ Object.new, Object.new ],
          skipped: [ Object.new ],
          high_risk: []
        )
      end
    end
  end

  def with_method_stub(klass, method_name, replacement)
    original = klass.instance_method(method_name)
    klass.define_method(method_name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    klass.define_method(method_name, original)
  end

  def with_singleton_stub(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def capture_rails_logger
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end

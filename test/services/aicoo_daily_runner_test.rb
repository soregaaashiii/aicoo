require "test_helper"

class AicooDailyRunnerTest < ActiveSupport::TestCase
  setup do
    AicooAutoRevisionSetting.delete_all
    AutoRevisionQueueRun.delete_all
    AutoRevisionTask.delete_all
    ActionCandidate.update_all(status: "done")
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
      assert_match "AutoRevisionQueue skipped reason=disabled", run.run_log
      assert_equal 0, AutoRevisionQueueRun.count
      assert_equal %i[analytics datahub import adjust_all generate insight evaluate snapshot queue meta_snapshot calibration], order
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

  test "partial failed run when analytics has failed fetch run" do
    order = []
    target_date = Date.new(2026, 6, 21)
    adjuster = fake_adjuster(order)
    generator_result = MetricActionCandidateGenerator::Result.new(created: [], skipped: [])

    stub_daily_steps(order:, adjuster:, generator_results: [ generator_result ], evaluated_results: [], analytics_status: "failed") do
      run = AicooDailyRunner.run!(target_date:, source: "cron")

      assert_equal "partial_failed", run.status
      assert_equal "cron", run.source
      assert_equal 0, run.analytics_fetch_count
      assert_match "Analytics fetched success=0 failed=1", run.run_log
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
    end
  end

  test "failed run stores error message" do
    error = RuntimeError.new("boom")

    with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:) { raise error }) do
      assert_raises(RuntimeError) do
        AicooDailyRunner.run!(target_date: Date.new(2026, 6, 21))
      end
    end

    run = AicooDailyRun.last
    assert_equal "failed", run.status
    assert_match "RuntimeError: boom", run.error_message
    assert_match "Daily Run failed", run.run_log
  end

  test "does not start duplicate running daily run for same target date" do
    target_date = Date.new(2026, 6, 21)
    existing = AicooDailyRun.create!(target_date:, status: "running", started_at: Time.current)

    with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:) { raise "should not be called" }) do
      assert_equal existing, AicooDailyRunner.run!(target_date:)
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

  def stub_daily_steps(order:, adjuster:, generator_results:, evaluated_results:, analytics_status: "success", calibration_error: nil)
    with_singleton_stub(AicooAnalytics::DailyFetchJob, :perform_now, -> { fake_analytics_fetch(order, analytics_status) }) do
      with_singleton_stub(AicooDataHub::DailyCollector, :new, -> { fake_datahub_collector(order) }) do
        with_singleton_stub(BusinessMetricDailyImporter, :import_all!, ->(date:) {
          order << :import
          [ Object.new, Object.new ]
        }) do
          with_singleton_stub(ProxyScoreWeightAdjuster, :new, -> { adjuster }) do
            with_singleton_stub(MetricActionCandidateGenerator, :generate_all!, -> {
              order << :generate
              generator_results
            }) do
              with_singleton_stub(AicooInsight::Generator, :generate_all!, ->(source:) {
                order << :insight
                AicooInsight::Generator::Result.new(created: [ Object.new ], skipped: [ Object.new, Object.new ])
              }) do
                with_singleton_stub(ActionResultEvaluator, :evaluate_pending!, -> {
                  order << :evaluate
                  evaluated_results
                }) do
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

  def fake_analytics_fetch(order, status)
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
      finished_at: Time.current
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
end

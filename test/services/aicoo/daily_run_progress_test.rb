require "test_helper"

module Aicoo
  class DailyRunProgressTest < ActiveSupport::TestCase
    setup do
      Aicoo::DailyRunProgress::DurationAverageCache.reset
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
      @now = Time.zone.parse("2026-07-24 10:00:00")
      @averages = Aicoo::DailyRunProgress::STEP_NAMES.index_with { 120.0 }
    end

    test "starts at zero percent" do
      run = create_run(status: "pending", started_at: nil)

      progress = build_progress(run)

      assert_equal 0, progress.progress_percent
      assert_not progress.completed?
    end

    test "completed step and business progress increase percent" do
      run = create_run
      create_step(run, "analytics_fetch", status: "success", duration_seconds: 30)
      create_step(
        run,
        "business_metrics_import",
        status: "running",
        started_at: @now - 20.seconds,
        metadata: {
          current_business_id: businesses(:suelog).id,
          current_business_name: businesses(:suelog).name,
          current_business_index: 2,
          total_business_count: 4
        }
      )

      progress = build_progress(run)

      assert_operator progress.progress_percent, :>, 0
      assert_equal businesses(:suelog).id, progress.current_business_id
      assert_equal businesses(:suelog).name, progress.current_business_name
      assert_equal 2, progress.current_business_index
      assert_equal 4, progress.total_business_count
      assert_equal "#{businesses(:suelog).name} 2 / 4", progress.business_label
    end

    test "weights short and long steps by expected duration" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "success",
        duration_seconds: 10,
        metadata: plan_metadata(%w[analytics_fetch datahub_collect])
      )
      create_step(run, "datahub_collect", status: "running")

      progress = build_progress(run, averages: {
        "analytics_fetch" => 10,
        "datahub_collect" => 90
      })

      assert_equal 10, progress.progress_percent
      assert_not_equal 50, progress.progress_percent
    end

    test "calculates weighted progress from completed duration and current fraction" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "success",
        duration_seconds: 1_800,
        metadata: plan_metadata(%w[analytics_fetch business_metrics_import action_generation])
      )
      create_step(
        run,
        "business_metrics_import",
        status: "running",
        metadata: { current_business_index: 1, total_business_count: 2 }
      )

      progress = build_progress(run, averages: {
        "analytics_fetch" => 1_800,
        "business_metrics_import" => 1_200,
        "action_generation" => 600
      })

      assert_equal 67, progress.progress_percent
      assert_equal 50, progress.current_step_percent
      assert_equal 1_200, progress.remaining_seconds
    end

    test "long running step advances and eta decreases with business progress" do
      run = create_run
      step = create_step(
        run,
        "business_metrics_import",
        status: "running",
        metadata: plan_metadata(%w[business_metrics_import]).merge(
          current_business_index: 1,
          total_business_count: 4
        )
      )
      first = build_progress(run, averages: { "business_metrics_import" => 1_200 })

      step.update!(metadata: step.metadata.merge(
        "current_business_index" => 3,
        "total_business_count" => 4
      ))
      second = build_progress(run.reload, averages: { "business_metrics_import" => 1_200 })

      assert_equal 25, first.progress_percent
      assert_equal 75, second.progress_percent
      assert_operator second.remaining_seconds, :<, first.remaining_seconds
    end

    test "excludes steps outside the stored execution plan" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "success",
        duration_seconds: 30,
        metadata: plan_metadata(%w[analytics_fetch datahub_collect])
      )
      create_step(run, "datahub_collect", status: "running")

      progress = build_progress(run, averages: {
        "analytics_fetch" => 30,
        "datahub_collect" => 30,
        "insight_generation" => 3_600
      })

      assert_equal 50, progress.progress_percent
      assert_equal 30, progress.remaining_seconds
    end

    test "excludes a pre-run skipped step from the denominator" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "skipped",
        duration_seconds: 1,
        metadata: plan_metadata(%w[analytics_fetch datahub_collect]).merge(progress_applicable: false)
      )
      create_step(
        run,
        "datahub_collect",
        status: "running",
        metadata: { current_position: 1, total_count: 2 }
      )

      progress = build_progress(run, averages: {
        "analytics_fetch" => 10,
        "datahub_collect" => 90
      })

      assert_equal 50, progress.progress_percent
      assert_equal 45, progress.remaining_seconds
    end

    test "uses candidate progress when business progress is unavailable" do
      run = create_run
      create_step(
        run,
        "action_generation",
        status: "running",
        metadata: plan_metadata(%w[action_generation]).merge(
          current_candidate_count: 40,
          total_candidate_count: 160
        )
      )

      progress = build_progress(run, averages: { "action_generation" => 400 })

      assert_equal 25, progress.progress_percent
      assert_equal 25, progress.current_step_percent
      assert_equal 300, progress.remaining_seconds
    end

    test "prefers business progress when business and candidate counts both exist" do
      run = create_run
      create_step(
        run,
        "action_generation",
        status: "running",
        metadata: plan_metadata(%w[action_generation]).merge(
          current_business_index: 3,
          total_business_count: 4,
          current_candidate_count: 10,
          total_candidate_count: 100
        )
      )

      progress = build_progress(run, averages: { "action_generation" => 400 })

      assert_equal 75, progress.progress_percent
      assert_equal 75, progress.current_step_percent
    end

    test "uses step-specific counts after business and candidate progress" do
      run = create_run
      create_step(
        run,
        "insight_generation",
        status: "running",
        metadata: plan_metadata(%w[insight_generation]).merge(
          insight_generation_progress: { current_position: 2, total_count: 5 }
        )
      )

      progress = build_progress(run, averages: { "insight_generation" => 500 })

      assert_equal 40, progress.progress_percent
      assert_equal 300, progress.remaining_seconds
    end

    test "uses zero current fraction when no internal progress is available" do
      run = create_run
      create_step(
        run,
        "insight_generation",
        status: "running",
        metadata: plan_metadata(%w[insight_generation])
      )

      progress = build_progress(run, averages: { "insight_generation" => 500 })

      assert_equal 0, progress.progress_percent
      assert_equal 0, progress.current_step_percent
      assert_equal 500, progress.remaining_seconds
    end

    test "saved progress prevents regression when duration averages change" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "success",
        duration_seconds: 30,
        metadata: plan_metadata(%w[analytics_fetch insight_generation]).merge(progress_percent: 70)
      )
      create_step(run, "insight_generation", status: "running")

      progress = build_progress(run, averages: {
        "analytics_fetch" => 10,
        "insight_generation" => 90
      })

      assert_equal 70, progress.progress_percent
    end

    test "falls back to sixty seconds when no duration history exists" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "running",
        metadata: plan_metadata(%w[analytics_fetch datahub_collect])
      )

      progress = build_progress(run, averages: {})

      assert_equal 0, progress.progress_percent
      assert_equal 120, progress.remaining_seconds
    end

    test "uses the current run successful-step average before sixty-second fallback" do
      run = create_run
      create_step(
        run,
        "analytics_fetch",
        status: "success",
        duration_seconds: 30,
        metadata: plan_metadata(%w[analytics_fetch datahub_collect insight_generation])
      )
      create_step(run, "datahub_collect", status: "running")

      progress = build_progress(run, averages: {})

      assert_equal 33, progress.progress_percent
      assert_equal 60, progress.remaining_seconds
    end

    test "single and collection presenters return the same progress" do
      run = create_run
      create_step(
        run,
        "business_metrics_import",
        status: "running",
        metadata: plan_metadata(%w[analytics_fetch business_metrics_import]).merge(
          current_business_index: 2,
          total_business_count: 4
        )
      )
      run_with_steps = AicooDailyRun.includes(:aicoo_daily_run_steps).find(run.id)

      single = Aicoo::DailyRunProgress.call(run_with_steps, averages: @averages, now: @now)
      collection = Aicoo::DailyRunProgress.for_runs([ run_with_steps ], averages: @averages, now: @now).fetch(run_with_steps)

      assert_equal single.progress_percent, collection.progress_percent
      assert_equal single.remaining_seconds, collection.remaining_seconds
    end

    test "shows candidate progress during action generation" do
      run = create_run
      create_step(
        run,
        "action_generation",
        status: "running",
        metadata: {
          current_business_index: 25,
          total_business_count: 100,
          current_candidate_count: 40,
          total_candidate_count: 160
        }
      )

      progress = build_progress(run)

      assert_equal "Action Generation", progress.current_step_label
      assert_equal 40, progress.current_candidate_count
      assert_equal 160, progress.total_candidate_count
      assert_equal "40 / 約160", progress.candidate_label
    end

    test "uses historical step duration for eta" do
      run = create_run(started_at: @now - 1.minute)
      create_step(run, "analytics_fetch", status: "running", started_at: @now - 30.seconds)

      progress = build_progress(run)

      assert_operator progress.remaining_seconds, :>, 0
      assert_equal @now + progress.remaining_seconds, progress.estimated_finish_at
      assert_match(/約\d+分|1分未満/, progress.remaining_label)
    end

    test "completed run is one hundred percent with summary counts" do
      run = create_run(
        status: "success",
        started_at: @now - 10.minutes,
        finished_at: @now,
        action_candidates_generated_count: 8
      )
      create_step(
        run,
        "business_metrics_import",
        status: "success",
        duration_seconds: 60,
        metadata: { total_business_count: 12, processed_business_count: 12 }
      )
      create_step(
        run,
        "auto_revision_queue",
        status: "success",
        duration_seconds: 30,
        metadata: { generated_tasks_count: 3 }
      )

      progress = build_progress(run)

      assert_equal 100, progress.progress_percent
      assert progress.completed?
      assert_equal 12, progress.business_count
      assert_equal 8, progress.candidate_count
      assert_equal 3, progress.revision_queue_count
      assert_equal "10分0秒", progress.elapsed_label
      assert progress.successful?
      assert_equal "完了", progress.status_label
      assert_equal "success", progress.state
    end

    test "partial failed run is complete but not successful" do
      run = create_run(
        status: "partial_failed",
        started_at: @now - 10.minutes,
        finished_at: @now,
        error_message: "one step failed"
      )
      create_step(run, "analytics_fetch", status: "failed", error_message: "fetch failed")

      progress = build_progress(run)

      assert_equal 100, progress.progress_percent
      assert progress.completed?
      assert progress.partial_failed?
      assert_not progress.successful?
      assert_equal "実行終了・一部失敗", progress.status_label
      assert_equal "partial-failed", progress.state
    end

    test "failed run retains intermediate progress and retry count" do
      run = create_run(status: "failed", retry_count: 2, error_message: "Timeout")
      create_step(run, "analytics_fetch", status: "success", duration_seconds: 30)
      create_step(
        run,
        "business_metrics_import",
        status: "failed",
        duration_seconds: 45,
        metadata: {
          current_business_id: businesses(:suelog).id,
          current_business_name: businesses(:suelog).name,
          current_business_index: 122,
          total_business_count: 183
        },
        error_message: "Timeout"
      )

      before_retry = build_progress(run)
      run.update!(retry_count: 3)
      after_retry = build_progress(run.reload)

      assert_operator before_retry.progress_percent, :>, 0
      assert_operator before_retry.progress_percent, :<, 100
      assert_equal before_retry.progress_percent, after_retry.progress_percent
      assert_equal 3, after_retry.retry_count
      assert_equal "business_metrics_import", after_retry.failed_step
      assert_equal "Business Metrics Import", after_retry.current_step_label
      assert_equal 122, after_retry.current_business_index
      assert_equal 183, after_retry.total_business_count
      assert_equal "Timeout", after_retry.failure_reason
      assert_equal "実行終了・失敗", after_retry.status_label
      assert_equal "failed", after_retry.state
    end

    test "stuck run retains saved weighted progress below one hundred" do
      run = create_run(status: "stuck", retry_count: 1, error_message: "heartbeat expired")
      create_step(
        run,
        "insight_generation",
        status: "running",
        metadata: plan_metadata(%w[analytics_fetch insight_generation]).merge(progress_percent: 63)
      )

      progress = build_progress(run)

      assert_equal 63, progress.progress_percent
      assert progress.stuck?
      assert_equal "停止中", progress.status_label
      assert_equal "stuck", progress.state
    end

    test "old run without progress metadata remains displayable" do
      run = create_run(status: "failed", finished_at: @now)
      create_step(run, "analytics_fetch", status: "success", duration_seconds: 60)
      create_step(run, "datahub_collect", status: "failed", duration_seconds: 60)

      progress = build_progress(run, averages: {})

      assert_operator progress.progress_percent, :>, 0
      assert_operator progress.progress_percent, :<, 100
      assert_equal "datahub_collect", progress.failed_step
    end

    test "duration samples are loaded once within one execution context" do
      history_run = create_run(status: "success", finished_at: @now)
      create_step(history_run, "analytics_fetch", status: "success", duration_seconds: 45)
      Aicoo::DailyRunProgress::DurationAverageCache.reset
      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        queries << sql if sql.include?("aicoo_daily_run_steps") && sql.include?("AVG") && sql.include?("LIMIT")
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Aicoo::DailyRunProgress.historical_averages
        Aicoo::DailyRunProgress.historical_averages
      end

      assert_equal 1, queries.size
    end

    test "execution status keeps a recent post run step visible" do
      run = create_run(status: "success", finished_at: @now)
      create_step(run, "analytics_fetch", status: "success", duration_seconds: 30)
      create_step(run, "auto_revision_queue", status: "running", started_at: 10.seconds.ago)

      status = Aicoo::DailyRunExecutionStatus.call
      row = status.rows.find { |item| item.run_id == run.id }

      assert row
      assert row.progress.active?
      assert_operator row.progress.progress_percent, :<, 100
    end

    test "completed run with a stale running step remains complete" do
      run = create_run(status: "success", finished_at: 2.hours.ago)
      create_step(run, "business_metrics_import", status: "running", started_at: @now - 2.hours)

      progress = build_progress(run)
      status = Aicoo::DailyRunExecutionStatus.call

      assert progress.completed?
      assert_equal 100, progress.progress_percent
      assert_not status.rows.any? { |item| item.run_id == run.id }
    end

    private

    def create_run(status: "running", started_at: @now - 2.minutes, finished_at: nil, **attributes)
      AicooDailyRun.create!(
        {
          target_date: Date.new(2026, 7, 23),
          status:,
          source: "manual",
          started_at:,
          finished_at:
        }.merge(attributes)
      )
    end

    def create_step(run, name, status:, started_at: @now - 1.minute, duration_seconds: nil, metadata: {}, error_message: nil)
      run.aicoo_daily_run_steps.create!(
        step_name: name,
        status:,
        started_at:,
        finished_at: status == "running" ? nil : @now,
        duration_seconds:,
        metadata:,
        error_message:
      )
    end

    def build_progress(run, averages: @averages)
      Aicoo::DailyRunProgress.call(
        run,
        steps: run.aicoo_daily_run_steps.to_a,
        averages:,
        now: @now
      )
    end

    def plan_metadata(step_names)
      {
        Aicoo::DailyRunProgress::STEP_PLAN_METADATA_KEY =>
          Aicoo::DailyRunProgress::STEP_NAMES.index_with { |name| step_names.include?(name) }
      }
    end
  end
end

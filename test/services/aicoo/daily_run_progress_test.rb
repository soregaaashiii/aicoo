require "test_helper"

module Aicoo
  class DailyRunProgressTest < ActiveSupport::TestCase
    setup do
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
    end

    test "execution status keeps post run queue step visible while it is running" do
      run = create_run(status: "success", finished_at: @now)
      create_step(run, "analytics_fetch", status: "success", duration_seconds: 30)
      create_step(run, "auto_revision_queue", status: "running", started_at: @now - 10.seconds)

      status = Aicoo::DailyRunExecutionStatus.call
      row = status.rows.find { |item| item.run_id == run.id }

      assert status.running?
      assert row
      assert row.progress.active?
      assert_operator row.progress.progress_percent, :<, 100
      assert_equal "Auto Revision Queue", row.current_step_name
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

    def build_progress(run)
      Aicoo::DailyRunProgress.call(
        run,
        steps: run.aicoo_daily_run_steps.to_a,
        averages: @averages,
        now: @now
      )
    end
  end
end

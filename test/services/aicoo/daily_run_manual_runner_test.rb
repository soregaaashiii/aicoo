require "test_helper"

module Aicoo
  class DailyRunManualRunnerTest < ActiveSupport::TestCase
    setup do
      @run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "cron",
        started_at: 1.hour.ago,
        finished_at: 30.minutes.ago
      )
      @step = @run.aicoo_daily_run_steps.create!(
        step_name: "article_opportunity_analysis",
        status: "failed",
        started_at: 1.hour.ago,
        finished_at: 30.minutes.ago
      )
    end

    test "dry-run does not execute recovery" do
      called = false

      with_step_recovery_stub(->(**) {
        called = true
        raise "should not recover in dry-run"
      }) do
        result = DailyRunManualRunner.call(target_date: @run.target_date, target_step: @step.step_name, apply: false)

        assert_equal "dry_run", result.mode
        assert_equal [ "article_opportunity_analysis" ], result.selected_steps
        assert_empty result.executed_steps
      end

      assert_not called
    end

    test "apply executes recoverable target step and stores manual bypass metadata" do
      called = false

      with_step_recovery_stub(->(daily_run:, step_name:) {
        called = true
        assert_equal @run, daily_run
        assert_equal "article_opportunity_analysis", step_name
        StepRecoveryService::Result.new(
          success: true,
          message: "Article opportunity analysis step recovery completed",
          started_at: Time.current,
          finished_at: Time.current,
          duration_seconds: 0,
          error_message: nil
        )
      }) do
        result = DailyRunManualRunner.call(target_date: @run.target_date, target_step: @step.step_name, apply: true, requested_by: "test")

        assert result.success
        assert_equal "apply", result.mode
        assert_equal [ "article_opportunity_analysis" ], result.selected_steps
      end

      assert called
      metadata = @step.reload.metadata.fetch("manual_retry_bypass")
      assert_equal "manual", metadata["execution_source"]
      assert_equal true, metadata["retry_limit_bypassed"]
      assert_equal "explicit_manual_run", metadata["retry_limit_bypass_reason"]
      assert_includes @run.reload.run_log, "Manual Daily Run recovery requested"
    end

    test "active running run blocks manual recovery" do
      AicooDailyRun.create!(
        target_date: @run.target_date,
        status: "running",
        source: "manual",
        started_at: Time.current,
        updated_at: Time.current
      )

      result = DailyRunManualRunner.call(target_date: @run.target_date, target_step: @step.step_name, apply: true)

      assert_not result.success
      assert_empty result.selected_steps
      assert_includes result.message, "現在実行中"
    end

    private

    def with_step_recovery_stub(replacement)
      original = StepRecoveryService.method(:run!)
      StepRecoveryService.define_singleton_method(:run!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
      yield
    ensure
      StepRecoveryService.define_singleton_method(:run!) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end

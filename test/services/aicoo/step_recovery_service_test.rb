require "test_helper"

module Aicoo
  class StepRecoveryServiceTest < ActiveSupport::TestCase
    setup do
      @daily_run = AicooDailyRun.create!(
        target_date: Date.current,
        status: "partial_failed",
        source: "manual",
        started_at: 10.minutes.ago,
        finished_at: 5.minutes.ago
      )
    end

    test "calibration recovery runs calibration engine and updates step" do
      step = create_step("calibration")
      result_object = Aicoo::CalibrationEngine::Result.new(calibrations: [ Object.new ], logs: [ Object.new, Object.new ])

      with_calibration_stub(->(source:, aicoo_daily_run:) {
        assert_equal "step_recovery", source
        assert_equal @daily_run, aicoo_daily_run
        result_object
      }) do
        result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "calibration")

        assert result.success
        assert_match "Calibration step recovery completed successfully", result.message
        step.reload
        assert_equal 1, step.recovery_attempt_count
        assert_equal "success", step.last_recovery_status
        assert_not step.recovery_locked?
        assert step.last_recovery_at.present?
        assert_equal true, @daily_run.reload.calibration_ran
        assert_equal 1, @daily_run.updated_calibration_count
        assert_equal 2, @daily_run.calibration_log_count
      end
    end

    test "recovery failure stores error on step" do
      step = create_step("calibration")

      with_calibration_stub(->(source:, aicoo_daily_run:) { raise RuntimeError, "calibration boom" }) do
        result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "calibration")

        assert_not result.success
        assert_match "RuntimeError: calibration boom", result.error_message
        step.reload
        assert_equal 1, step.recovery_attempt_count
        assert_equal "failed", step.last_recovery_status
        assert_not step.recovery_locked?
        assert_match "RuntimeError: calibration boom", step.last_recovery_message
      end
    end

    test "locked step does not run recovery" do
      step = create_step("calibration")
      step.update!(recovery_locked: true, recovery_locked_at: Time.current)

      result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "calibration")

      assert_not result.success
      assert_equal "Recovery is already running", result.message
      step.reload
      assert step.recovery_locked?
      assert_equal 0, step.recovery_attempt_count
    end

    test "cooldown step does not run recovery" do
      step = create_step("calibration")
      step.update!(
        recovery_attempt_count: 1,
        last_recovery_at: 1.minute.ago,
        last_recovery_status: "failed"
      )

      result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "calibration")

      assert_not result.success
      assert_equal "Recovery cooldown active", result.message
      assert_equal 1, step.reload.recovery_attempt_count
    end

    test "recovery limit prevents execution" do
      step = create_step("calibration")
      step.update!(
        recovery_attempt_count: 3,
        last_recovery_at: 10.minutes.ago,
        last_recovery_status: "failed"
      )

      result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "calibration")

      assert_not result.success
      assert_equal "Recovery limit reached", result.message
      assert_equal 3, step.reload.recovery_attempt_count
    end

    test "non recoverable step is skipped" do
      step = create_step("analytics_fetch")

      result = StepRecoveryService.run!(daily_run: @daily_run, step_name: "analytics_fetch")

      assert_not result.success
      assert_match "再実行不可", result.message
      step.reload
      assert_equal "skipped", step.last_recovery_status
      assert_equal 1, step.recovery_attempt_count
    end

    private

    def create_step(step_name)
      @daily_run.aicoo_daily_run_steps.create!(
        step_name:,
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "failed"
      )
    end

    def with_calibration_stub(replacement)
      original = Aicoo::CalibrationEngine.method(:run!)
      Aicoo::CalibrationEngine.define_singleton_method(:run!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
      yield
    ensure
      Aicoo::CalibrationEngine.define_singleton_method(:run!) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end

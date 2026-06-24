require "test_helper"

module Aicoo
  class DailyRunHealthSummaryTest < ActiveSupport::TestCase
    setup do
      ActionCandidate.update_all(created_at: 10.days.ago, status: "done")
      AicooDailyRun.delete_all
      ActionPredictionCalibration.delete_all
      ActionPredictionCalibrationLog.delete_all
    end

    test "today success daily run is healthy" do
      create_daily_run(status: "success", updated_calibration_count: 2)
      create_action_candidate
      ActionPredictionCalibrationLog.create!(
        action_type: "seo_article",
        old_profit_calibration_factor: 1,
        new_profit_calibration_factor: 1.1,
        old_probability_calibration_factor: 1,
        new_probability_calibration_factor: 1,
        sample_count: 10,
        calculated_at: Time.current,
        source: "daily_run"
      )

      summary = DailyRunHealthSummary.new.call

      assert_equal "healthy", summary.health_status
      assert_equal "success", summary.latest_status
      assert_equal 1, summary.today_run_count
      assert_equal 1, summary.today_success_count
      assert_equal 1, summary.today_generated_action_candidates_count
      assert_equal 2, summary.today_calibration_updated_count
      assert_equal 1, summary.today_calibration_log_count
      assert_equal 1, summary.today_calibration_log_counts_by_source.fetch("daily_run")
      assert_empty summary.warnings
    end

    test "latest partial failed daily run is warning" do
      create_daily_run(status: "partial_failed", error_message: "analytics failed")
      create_action_candidate

      summary = DailyRunHealthSummary.new.call

      assert_equal "warning", summary.health_status
      assert_equal "partial_failed", summary.latest_status
      assert_includes summary.warnings, "Daily Runがpartial_failedです。"
      assert_equal "失敗ステップを確認してください", summary.recommended_action
    end

    test "latest failed daily run is critical" do
      create_daily_run(status: "failed", error_message: "boom")
      create_action_candidate

      summary = DailyRunHealthSummary.new.call

      assert_equal "critical", summary.health_status
      assert_equal "failed", summary.latest_status
      assert_includes summary.warnings, "Daily Runがfailed/stuckです。"
      assert_equal "Daily Run詳細を確認してください", summary.recommended_action
    end

    test "zero action candidates today adds warning" do
      create_daily_run(status: "success")

      summary = DailyRunHealthSummary.new.call

      assert_equal "attention", summary.health_status
      assert_equal 0, summary.today_generated_action_candidates_count
      assert_includes summary.warnings, "今日のActionCandidate生成数が0です。"
      assert_equal "Daily Runの生成ステップを確認してください", summary.recommended_action
    end

    test "pending calibration adds attention counts" do
      create_daily_run(status: "success")
      create_action_candidate
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        pending_profit_calibration_factor: 2.5,
        pending_probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        confidence_level: "low",
        approval_requested_at: Time.current
      )

      summary = DailyRunHealthSummary.new.call

      assert_equal "attention", summary.health_status
      assert_equal 1, summary.today_pending_calibration_count
      assert_equal 1, summary.danger_pending_calibration_count
      assert_equal 1, summary.low_confidence_pending_calibration_count
      assert_includes summary.warnings, "承認待ち補正があります。"
      assert_includes summary.warnings, "dangerの承認待ち補正があります。"
      assert_equal "Calibration承認待ちを確認してください", summary.recommended_action
    end

    test "failed and slow steps are included in health summary" do
      run = create_daily_run(status: "success")
      create_action_candidate
      run.aicoo_daily_run_steps.create!(
        step_name: "action_generation",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "generation boom"
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "success",
        started_at: 3.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 120
      )

      summary = DailyRunHealthSummary.new.call

      assert_equal "critical", summary.health_status
      assert_equal 2, summary.step_count
      assert_equal 1, summary.failed_step_count
      assert_equal 0, summary.skipped_step_count
      assert_equal [ "action_generation" ], summary.failed_steps.map(&:step_name)
      assert_includes summary.slow_steps.map(&:step_name), "calibration"
      assert_includes summary.warnings, "Daily Runの一部ステップが失敗しています。"
      assert_includes summary.warnings, "Daily Runに遅いステップがあります。"
    end

    test "recovery metadata is included in health summary" do
      run = create_daily_run(status: "partial_failed")
      create_action_candidate
      run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "calibration boom",
        recovery_attempt_count: 3,
        last_recovery_at: Time.current,
        last_recovery_status: "failed",
        last_recovery_message: "still broken"
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "score_snapshot",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        recovery_locked: true,
        recovery_locked_at: Time.current
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "owner_task_digest",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        recovery_attempt_count: 1,
        last_recovery_at: 1.minute.ago,
        last_recovery_status: "failed"
      )

      summary = DailyRunHealthSummary.new.call

      assert_equal 3, summary.recoverable_failed_steps_count
      assert summary.last_recovery_at.present?
      assert_equal 2, summary.recovery_failures_count
      assert_equal 1, summary.locked_recovery_count
      assert_equal 2, summary.cooldown_recovery_count
      assert_equal 1, summary.recovery_limit_reached_count
      assert_includes summary.warnings, "3件の復旧可能な失敗ステップがあります。"
      assert_includes summary.warnings, "Daily Run step recoveryに失敗があります。"
      assert_includes summary.warnings, "1 steps reached recovery limit"
      assert_includes summary.warnings, "1 step is currently locked"
    end

    private

    def create_daily_run(attributes = {})
      now = Time.current
      AicooDailyRun.create!(
        {
          target_date: Date.current,
          status: "success",
          source: "manual",
          started_at: now - 5.minutes,
          finished_at: now,
          retry_count: 0,
          analytics_fetch_count: 1,
          snapshot_count: 1,
          insight_generated_count: 1,
          updated_calibration_count: 0,
          calibration_log_count: 0,
          pending_calibration_count: 0
        }.merge(attributes)
      )
    end

    def create_action_candidate(attributes = {})
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          title: "Health summary candidate",
          action_type: "seo_article",
          status: "idea",
          immediate_value_yen: 5_000,
          success_probability: 0.5,
          expected_hours: 1,
          final_score: 1_500
        }.merge(attributes)
      )
    end
  end
end

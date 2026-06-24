require "test_helper"

module Aicoo
  class OwnerTaskInboxTest < ActiveSupport::TestCase
    setup do
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
    end

    test "returns action candidates waiting for owner approval" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Owner inbox approval candidate",
        status: "idea",
        action_type: "build_lp",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )

      tasks = OwnerTaskInbox.new.call.tasks

      task = tasks.find { |item| item.task_type == "action_candidate_approval" && item.title == candidate.title }
      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.action_candidate_path(candidate), task.target_path
      assert_equal [ "承認", "却下", "詳細を見る" ], task.quick_actions.map(&:label)
      assert_equal Rails.application.routes.url_helpers.approve_action_candidate_path(candidate), task.quick_actions.first.path
    end

    test "returns calibration pending and danger as critical" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        warning_reason: "利益補正係数が極端です",
        approval_requested_at: Time.current
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "calibration_approval" }

      assert task
      assert_equal "critical", task.priority
      assert_includes task.reason, "極端"
      assert_equal [ "承認", "却下", "補正詳細を見る" ], task.quick_actions.map(&:label)
    end

    test "returns failed and stuck daily runs as critical" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "failed",
        source: "manual",
        error_message: "boom",
        finished_at: Time.current
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_failure" }

      assert task
      assert_equal "critical", task.priority
      assert_equal Rails.application.routes.url_helpers.aicoo_daily_run_path(run), task.target_path
      assert_includes task.reason, "boom"
      assert_equal [ "再実行", "詳細を見る" ], task.quick_actions.map(&:label)
    end

    test "returns daily run step failures as tasks" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "success",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "action_generation",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "generation boom"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_step_failure" }

      assert task
      assert_equal "critical", task.priority
      assert_match "action_generation", task.title
      assert_match "generation boom", task.reason
      assert_equal Rails.application.routes.url_helpers.aicoo_daily_run_path(run), task.target_path
    end

    test "returns recoverable daily run steps as recovery tasks" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      step = run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "calibration boom"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_step_recovery" }

      assert task
      assert_equal "high", task.priority
      assert_match "calibration", task.title
      assert_equal [ "復旧する", "Step Breakdownを見る" ], task.quick_actions.map(&:label)
      assert_equal Rails.application.routes.url_helpers.recover_aicoo_daily_run_step_path(run, step), task.quick_actions.first.path
    end

    test "returns recovery attention when recoverable step is unavailable" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "calibration boom",
        recovery_attempt_count: 1,
        last_recovery_at: 1.minute.ago,
        last_recovery_status: "failed"
      )

      tasks = OwnerTaskInbox.new.call.tasks
      attention = tasks.find { |item| item.task_type == "daily_run_recovery_attention" }

      assert attention
      assert_equal "high", attention.priority
      assert_match "Recovery cooldown active", attention.reason
      assert_not tasks.any? { |item| item.task_type == "daily_run_step_recovery" }
    end

    test "returns non pending calibration warnings without duplicating pending action type" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1
      )
      ActionPredictionCalibration.create!(
        action_type: "market_research",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        approval_status: "auto_applied",
        warning_level: "warning",
        warning_reason: "前回比50%以上"
      )

      tasks = OwnerTaskInbox.new.call.tasks

      assert_equal 1, tasks.count { |task| task.task_type == "calibration_approval" && task.title.include?("seo_article") }
      assert tasks.any? { |task| task.task_type == "calibration_warning" && task.title.include?("market_research") }
      assert_not tasks.any? { |task| task.task_type == "calibration_danger" && task.title.include?("seo_article") }
    end
  end
end

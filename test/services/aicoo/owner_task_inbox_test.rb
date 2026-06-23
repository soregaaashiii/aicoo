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

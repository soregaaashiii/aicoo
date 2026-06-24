require "test_helper"

module Aicoo
  class OwnerTaskDigestTest < ActiveSupport::TestCase
    setup do
      ActionCandidate.update_all(status: "done")
      ActionResult.delete_all
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
      OwnerTaskCompletionLog.delete_all
      create_healthy_daily_run
      create_done_today_candidate
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
    end

    test "critical task sets critical summary message" do
      create_pending_danger_calibration

      digest = OwnerTaskDigest.new.call

      assert_equal 1, digest.critical_count
      assert_equal "Criticalタスクがあります。最優先で確認してください。", digest.summary_message
      assert_includes digest.warnings, "危険度の高い評価式補正が承認待ちです。"
    end

    test "no open tasks returns no action summary" do
      digest = OwnerTaskDigest.new.call

      assert_equal 0, digest.total_open_tasks
      assert_nil digest.top_priority_task
      assert_nil digest.recommended_next_action
      assert_equal "現在、確認が必要なタスクはありません。", digest.summary_message
    end

    test "selects highest priority task before newer lower priority task" do
      AicooDailyRun.delete_all
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "failed",
        source: "manual",
        error_message: "boom",
        started_at: Time.current,
        created_at: Time.current,
        finished_at: Time.current
      )
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Newer high task",
        status: "idea",
        action_type: "other",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1,
        created_at: Time.current
      )

      digest = OwnerTaskDigest.new.call

      assert_equal "Daily Run #{run.target_date} がfailed", digest.top_priority_task.title
      assert_equal "詳細を見る", digest.recommended_next_action.label
    end

    test "counts completed logs for today and yesterday" do
      OwnerTaskCompletionLog.create!(
        task_type: "action_candidate_approval",
        target_type: "ActionCandidate",
        target_id: action_candidates(:nagazakicho_article).id,
        action_label: "承認",
        action_result: "success",
        message: "done today",
        completed_at: Time.current
      )
      OwnerTaskCompletionLog.create!(
        task_type: "calibration_approval",
        target_type: "ActionPredictionCalibration",
        target_id: 1,
        action_label: "却下",
        action_result: "success",
        message: "done yesterday",
        completed_at: Date.yesterday.noon
      )

      digest = OwnerTaskDigest.new.call

      assert_equal 1, digest.completed_today_count
      assert_equal 1, digest.completed_yesterday_count
    end

    test "includes result registration health in digest" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Digest result registration candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: 80.hours.ago,
        result_summary: "done"
      )

      digest = OwnerTaskDigest.new.call

      assert_equal 1, digest.result_registration_health.critical_count
      assert_equal "結果登録が滞留しています。", digest.summary_message
      assert_includes digest.warnings, "結果登録待ちが1件あります。"
    end

    private

    def create_pending_danger_calibration
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
    end

    def create_healthy_daily_run
      AicooDailyRun.create!(
        target_date: Date.current,
        status: "success",
        source: "manual",
        started_at: 10.minutes.ago,
        finished_at: 5.minutes.ago
      )
    end

    def create_done_today_candidate
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Today completed health baseline",
        status: "done",
        action_type: "other",
        immediate_value_yen: 1_000,
        success_probability: 1,
        expected_hours: 1
      )
    end
  end
end

require "test_helper"

module Admin
  class AicooCalibrationControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionPredictionCalibrationLog.delete_all
      ActionPredictionCalibration.delete_all
    end

    test "shows calibration dashboard" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        avg_predicted_profit_yen: 1_000,
        avg_actual_profit_yen: 800,
        profit_calibration_factor: 0.8,
        probability_calibration_factor: 1.1,
        avg_profit_error_rate: 0.2,
        confidence_level: "medium",
        warning_level: "warning",
        warning_reason: "利益補正係数が前回比50%以上変化しました",
        approval_status: "pending",
        pending_profit_calibration_factor: 0.7,
        pending_probability_calibration_factor: 0.9,
        approval_requested_at: Time.current,
        previous_profit_calibration_factor: 1.0,
        previous_probability_calibration_factor: 1.0,
        factor_changed_at: Time.current,
        last_calculated_at: Time.current
      )
      ActionPredictionCalibrationLog.create!(
        action_type: "seo_article",
        source: "daily_run",
        sample_count: 10,
        calculated_at: Time.current
      )

      get admin_aicoo_calibration_url

      assert_response :success
      assert_includes response.body, "評価関数補正"
      assert_includes response.body, "seo_article"
      assert_includes response.body, "最終自動実行日時"
      assert_includes response.body, "最終手動実行日時"
      assert_includes response.body, "Daily Run"
      assert_includes response.body, "confidence"
      assert_includes response.body, "warning_reason"
      assert_includes response.body, "approval_status"
      assert_includes response.body, "承認待ち件数"
      assert_includes response.body, "承認待ちだけ見る"
      assert_includes response.body, "承認"
      assert_includes response.body, "却下"
      assert_includes response.body, "補正によるランキング影響"
      assert_includes response.body, "action_type別 平均スコア変化"
      assert_includes response.body, "再計算"
    end

    test "recalculate button runs calibration engine" do
      create_result

      assert_difference("ActionPredictionCalibrationLog.count", 1) do
        post admin_aicoo_calibration_recalculate_url
      end

      assert_redirected_to admin_aicoo_calibration_url
      assert_match(/評価関数補正を/, flash[:notice])
    end

    test "approve applies pending calibration" do
      calibration = pending_calibration

      patch admin_aicoo_calibration_approve_url(calibration)

      assert_redirected_to admin_aicoo_calibration_url
      calibration.reload
      assert_equal "approved", calibration.approval_status
      assert_equal 0.7.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "approval", ActionPredictionCalibrationLog.last.source
    end

    test "reject keeps active calibration" do
      calibration = pending_calibration

      patch admin_aicoo_calibration_reject_url(calibration)

      assert_redirected_to admin_aicoo_calibration_url
      calibration.reload
      assert_equal "rejected", calibration.approval_status
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "rejected", ActionPredictionCalibrationLog.last.source
    end

    private

    def pending_calibration
      ActionPredictionCalibration.create!(
        action_type: "build_lp",
        sample_count: 10,
        profit_calibration_factor: 1.0,
        probability_calibration_factor: 1.0,
        pending_profit_calibration_factor: 0.7,
        pending_probability_calibration_factor: 0.9,
        approval_status: "pending",
        approval_requested_at: Time.current
      )
    end

    def create_result
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Calibration controller candidate",
        action_type: "seo_article",
        immediate_value_yen: 1_000,
        success_probability: 0.5,
        expected_hours: 1
      )

      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.yesterday,
        evaluated_on: Date.current,
        predicted_expected_profit_yen: 1_000,
        predicted_success_probability: 0.5,
        actual_profit_yen: 800,
        actual_revenue_yen: 800,
        evaluation_status: "evaluated"
      )
    end
  end
end

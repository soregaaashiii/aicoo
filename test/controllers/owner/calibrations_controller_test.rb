require "test_helper"

module Owner
  class CalibrationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionPredictionCalibrationLog.delete_all
      ActionPredictionCalibration.delete_all
    end

    test "approves pending calibration from owner tasks" do
      calibration = pending_calibration

      assert_difference("OwnerTaskCompletionLog.count", 1) do
        patch approve_owner_calibration_url(calibration)
      end

      assert_redirected_to owner_tasks_url
      calibration.reload
      assert_equal "approved", calibration.approval_status
      assert_equal 0.7.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "approval", ActionPredictionCalibrationLog.last.source
      assert_equal "Calibration『#{calibration.action_type}』を承認しました。pending係数が有効係数に反映されました。", flash[:notice]
      assert_equal "承認", OwnerTaskCompletionLog.last.action_label
    end

    test "rejects pending calibration from owner tasks" do
      calibration = pending_calibration

      assert_difference("OwnerTaskCompletionLog.count", 1) do
        patch reject_owner_calibration_url(calibration)
      end

      assert_redirected_to owner_tasks_url
      calibration.reload
      assert_equal "rejected", calibration.approval_status
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "rejected", ActionPredictionCalibrationLog.last.source
      assert_equal "Calibration『#{calibration.action_type}』を却下しました。有効係数は変更されませんでした。", flash[:notice]
      assert_equal "却下", OwnerTaskCompletionLog.last.action_label
    end

    private

    def pending_calibration
      ActionPredictionCalibration.create!(
        action_type: "owner_quick_action",
        sample_count: 10,
        profit_calibration_factor: 1.0,
        probability_calibration_factor: 1.0,
        pending_profit_calibration_factor: 0.7,
        pending_probability_calibration_factor: 0.9,
        approval_status: "pending",
        approval_requested_at: Time.current
      )
    end
  end
end

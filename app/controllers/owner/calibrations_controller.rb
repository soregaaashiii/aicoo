module Owner
  class CalibrationsController < ApplicationController
    def approve
      calibration = ActionPredictionCalibration.find(params[:id])
      calibration.approve!(note: params[:approval_note].presence || "Owner Task Quick Action")
      message = "Calibration『#{calibration.action_type}』を承認しました。pending係数が有効係数に反映されました。"
      OwnerTaskCompletionLog.record_success!(
        task_type: "calibration_approval",
        target: calibration,
        action_label: "承認",
        message:,
        metadata: {
          profit_calibration_factor: calibration.profit_calibration_factor,
          probability_calibration_factor: calibration.probability_calibration_factor
        }
      )

      redirect_to owner_tasks_path, notice: message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_tasks_path, alert: "補正の承認に失敗しました: #{e.record.errors.full_messages.to_sentence}"
    end

    def reject
      calibration = ActionPredictionCalibration.find(params[:id])
      calibration.reject!(note: params[:approval_note].presence || "Owner Task Quick Action")
      message = "Calibration『#{calibration.action_type}』を却下しました。有効係数は変更されませんでした。"
      OwnerTaskCompletionLog.record_success!(
        task_type: "calibration_approval",
        target: calibration,
        action_label: "却下",
        message:,
        metadata: {
          profit_calibration_factor: calibration.profit_calibration_factor,
          probability_calibration_factor: calibration.probability_calibration_factor
        }
      )

      redirect_to owner_tasks_path, notice: message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to owner_tasks_path, alert: "補正の却下に失敗しました: #{e.record.errors.full_messages.to_sentence}"
    end
  end
end

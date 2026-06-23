module Admin
  class AicooCalibrationController < ApplicationController
    def index
      load_calibration
    end

    def recalculate
      result = Aicoo::CalibrationEngine.run!
      redirect_to admin_aicoo_calibration_path,
                  notice: "評価関数補正を#{result.calibration_count} action_typeで再計算しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_aicoo_calibration_path,
                  alert: "評価関数補正の再計算に失敗しました: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def load_calibration
      @summary = ActionPredictionCalibrationSummary.new.call
      @calibrations = ActionPredictionCalibration.order(:action_type)
      @logs = ActionPredictionCalibrationLog.order(calculated_at: :desc, created_at: :desc).limit(30)
      @latest_manual_log = ActionPredictionCalibrationLog.where(source: "manual").order(calculated_at: :desc).first
      @latest_daily_run_log = ActionPredictionCalibrationLog.where(source: "daily_run").order(calculated_at: :desc).first
    end
  end
end

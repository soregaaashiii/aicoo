class AddRunSourceToActionPredictionCalibrationLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :action_prediction_calibration_logs, :source, :string, default: "manual", null: false
    add_reference :action_prediction_calibration_logs, :aicoo_daily_run, foreign_key: true
    add_index :action_prediction_calibration_logs, :source
  end
end

class AddMonitoringFieldsToActionPredictionCalibrations < ActiveRecord::Migration[8.0]
  def change
    add_column :action_prediction_calibrations, :confidence_level, :string, default: "low", null: false
    add_column :action_prediction_calibrations, :warning_level, :string, default: "none", null: false
    add_column :action_prediction_calibrations, :warning_reason, :text
    add_column :action_prediction_calibrations, :previous_profit_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :previous_probability_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :factor_changed_at, :datetime

    add_index :action_prediction_calibrations, :confidence_level
    add_index :action_prediction_calibrations, :warning_level
  end
end

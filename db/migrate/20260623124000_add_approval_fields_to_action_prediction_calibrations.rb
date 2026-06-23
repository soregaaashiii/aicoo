class AddApprovalFieldsToActionPredictionCalibrations < ActiveRecord::Migration[8.0]
  def change
    add_column :action_prediction_calibrations, :approval_status, :string, default: "auto_applied", null: false
    add_column :action_prediction_calibrations, :pending_profit_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :pending_probability_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :approved_profit_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :approved_probability_calibration_factor, :decimal
    add_column :action_prediction_calibrations, :approval_requested_at, :datetime
    add_column :action_prediction_calibrations, :approved_at, :datetime
    add_column :action_prediction_calibrations, :rejected_at, :datetime
    add_column :action_prediction_calibrations, :approval_note, :text

    add_index :action_prediction_calibrations, :approval_status
  end
end

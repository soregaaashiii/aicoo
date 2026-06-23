class CreateActionPredictionCalibrationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :action_prediction_calibration_logs do |t|
      t.string :action_type, null: false
      t.decimal :old_profit_calibration_factor
      t.decimal :new_profit_calibration_factor
      t.decimal :old_probability_calibration_factor
      t.decimal :new_probability_calibration_factor
      t.integer :sample_count
      t.decimal :avg_predicted_profit_yen
      t.decimal :avg_actual_profit_yen
      t.decimal :avg_profit_error_rate
      t.datetime :calculated_at

      t.timestamps
    end

    add_index :action_prediction_calibration_logs, :action_type
    add_index :action_prediction_calibration_logs, :calculated_at
  end
end

class CreateActionPredictionCalibrations < ActiveRecord::Migration[8.0]
  def change
    create_table :action_prediction_calibrations do |t|
      t.string :action_type, null: false
      t.integer :sample_count, default: 0, null: false
      t.decimal :avg_predicted_profit_yen
      t.decimal :avg_actual_profit_yen
      t.decimal :profit_calibration_factor, default: 1.0, null: false
      t.decimal :avg_predicted_success_probability
      t.decimal :actual_success_rate
      t.decimal :probability_calibration_factor, default: 1.0, null: false
      t.decimal :avg_profit_error_rate
      t.datetime :last_calculated_at

      t.timestamps
    end

    add_index :action_prediction_calibrations, :action_type, unique: true
  end
end

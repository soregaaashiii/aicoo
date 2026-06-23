class AddCalibrationFieldsToAicooDailyRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_daily_runs, :calibration_ran, :boolean, default: false, null: false
    add_column :aicoo_daily_runs, :calibration_started_at, :datetime
    add_column :aicoo_daily_runs, :calibration_finished_at, :datetime
    add_column :aicoo_daily_runs, :calibration_error, :text
    add_column :aicoo_daily_runs, :updated_calibration_count, :integer, default: 0, null: false
    add_column :aicoo_daily_runs, :calibration_log_count, :integer, default: 0, null: false
  end
end

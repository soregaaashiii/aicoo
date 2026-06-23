class AddPendingCalibrationCountToAicooDailyRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_daily_runs, :pending_calibration_count, :integer, default: 0, null: false
  end
end

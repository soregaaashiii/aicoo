class AddRecoveryLockToAicooDailyRunSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_daily_run_steps, :recovery_locked, :boolean, null: false, default: false
    add_column :aicoo_daily_run_steps, :recovery_locked_at, :datetime

    add_index :aicoo_daily_run_steps, :recovery_locked
  end
end

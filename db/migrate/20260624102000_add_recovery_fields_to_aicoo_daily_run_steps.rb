class AddRecoveryFieldsToAicooDailyRunSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_daily_run_steps, :recovery_attempt_count, :integer, null: false, default: 0
    add_column :aicoo_daily_run_steps, :last_recovery_at, :datetime
    add_column :aicoo_daily_run_steps, :last_recovery_status, :string
    add_column :aicoo_daily_run_steps, :last_recovery_message, :text

    add_index :aicoo_daily_run_steps, :last_recovery_status
  end
end

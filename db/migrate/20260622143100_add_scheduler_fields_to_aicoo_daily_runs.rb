class AddSchedulerFieldsToAicooDailyRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_daily_runs, :source, :string, null: false, default: "manual"
    add_column :aicoo_daily_runs, :retry_count, :integer, null: false, default: 0
    add_column :aicoo_daily_runs, :analytics_fetch_count, :integer, null: false, default: 0
    add_column :aicoo_daily_runs, :snapshot_count, :integer, null: false, default: 0
    add_column :aicoo_daily_runs, :insight_generated_count, :integer, null: false, default: 0

    add_index :aicoo_daily_runs, :source
  end
end

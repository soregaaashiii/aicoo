class AddDataPreparationQueueCountsToAicooDailyRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_daily_runs, :data_preparation_candidates_count, :integer, default: 0, null: false
    add_column :aicoo_daily_runs, :data_preparation_auto_queued_count, :integer, default: 0, null: false
  end
end

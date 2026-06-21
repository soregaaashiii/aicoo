class AddScoreSnapshotCountsToAicooDailyRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_daily_runs, :score_snapshots_created_count, :integer, default: 0, null: false
    add_column :aicoo_daily_runs, :score_snapshot_rank_up_count, :integer, default: 0, null: false
    add_column :aicoo_daily_runs, :score_snapshot_rank_down_count, :integer, default: 0, null: false
    add_column :aicoo_daily_runs, :score_snapshot_no_adjustment_count, :integer, default: 0, null: false
  end
end

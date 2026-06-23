class CreateAutoRevisionQueueRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :auto_revision_queue_runs do |t|
      t.references :aicoo_daily_run, foreign_key: true, index: false
      t.integer :generated_tasks_count, null: false, default: 0
      t.integer :skipped_candidates_count, null: false, default: 0
      t.integer :high_risk_candidates_count, null: false, default: 0
      t.datetime :executed_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auto_revision_queue_runs,
              :aicoo_daily_run_id,
              unique: true,
              where: "aicoo_daily_run_id IS NOT NULL"
    add_index :auto_revision_queue_runs, :executed_at
  end
end

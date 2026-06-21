class CreateAnalyticsFetchRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_fetch_runs do |t|
      t.references :analytics_source_setting, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :status, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :data_import_id
      t.integer :snapshot_count, default: 0, null: false
      t.integer :updated_neglect_loss_count, default: 0, null: false
      t.text :error_message

      t.timestamps
    end

    add_index :analytics_fetch_runs, :status
    add_index :analytics_fetch_runs, :source_type
  end
end

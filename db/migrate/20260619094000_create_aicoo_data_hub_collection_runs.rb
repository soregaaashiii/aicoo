class CreateAicooDataHubCollectionRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_data_hub_collection_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: "running"
      t.integer :snapshot_count, null: false, default: 0

      t.timestamps
    end

    add_index :aicoo_data_hub_collection_runs, :started_at
    add_index :aicoo_data_hub_collection_runs, :status
  end
end

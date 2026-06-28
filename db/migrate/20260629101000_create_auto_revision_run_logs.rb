class CreateAutoRevisionRunLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :auto_revision_run_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :auto_revision_task, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :auto_revision_mode, null: false
      t.string :risk_level
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :changed_files_count, default: 0, null: false
      t.decimal :codex_duration_seconds, precision: 10, scale: 2
      t.string :test_result
      t.string :deploy_result
      t.string :rollback_status
      t.string :base_commit_sha
      t.string :result_commit_sha
      t.text :message
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :auto_revision_run_logs, :status
    add_index :auto_revision_run_logs, :auto_revision_mode
    add_index :auto_revision_run_logs, :risk_level
    add_index :auto_revision_run_logs, :started_at
  end
end

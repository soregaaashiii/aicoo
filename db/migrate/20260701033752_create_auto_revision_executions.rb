class CreateAutoRevisionExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :auto_revision_executions do |t|
      t.references :auto_revision_task, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :prompt_snapshot
      t.text :result_summary
      t.text :error_message
      t.string :commit_sha
      t.string :pull_request_url
      t.string :deploy_url
      t.string :deploy_status
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auto_revision_executions, :status
    add_index :auto_revision_executions, :started_at
    add_index :auto_revision_executions, :finished_at
    add_index :auto_revision_executions, :commit_sha
  end
end

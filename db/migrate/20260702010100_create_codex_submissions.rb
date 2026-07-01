class CreateCodexSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_submissions do |t|
      t.references :auto_revision_task, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.references :business_execution_profile, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :workspace_name
      t.string :project_folder
      t.string :repository_url
      t.string :base_branch
      t.string :working_branch
      t.text :prompt
      t.jsonb :response_payload, null: false, default: {}
      t.text :error_message
      t.datetime :submitted_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :codex_submissions, :status
    add_index :codex_submissions, :project_folder
    add_index :codex_submissions, :submitted_at
    add_index :codex_submissions, :auto_revision_task_id, unique: true, name: "idx_codex_submissions_unique_task"
  end
end

class AddCodexExecutionTrackingToAutoRevisionTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_revision_tasks, :sent_to_codex_at, :datetime
    add_column :auto_revision_tasks, :codex_thread_url, :string
    add_column :auto_revision_tasks, :codex_session_label, :string
    add_column :auto_revision_tasks, :started_running_at, :datetime
    add_column :auto_revision_tasks, :last_checked_at, :datetime

    add_index :auto_revision_tasks, :sent_to_codex_at
    add_index :auto_revision_tasks, :started_running_at
    add_index :auto_revision_tasks, :last_checked_at
  end
end

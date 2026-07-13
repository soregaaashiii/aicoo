class AddCodexQueueControlsToAicooAutoRevisionSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_auto_revision_settings, :codex_queue_paused, :boolean, null: false, default: false
    add_column :aicoo_auto_revision_settings, :codex_queue_pause_reason, :text
    add_column :aicoo_auto_revision_settings, :codex_queue_paused_at, :datetime
  end
end

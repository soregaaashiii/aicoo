class AddResultIntakeFieldsToAutoRevisionTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_revision_tasks, :changed_files, :text
    add_column :auto_revision_tasks, :test_result, :text
    add_column :auto_revision_tasks, :codex_output, :text
  end
end

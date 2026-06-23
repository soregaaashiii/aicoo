class CreateOwnerTaskCompletionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :owner_task_completion_logs do |t|
      t.string :task_type, null: false
      t.string :target_type
      t.integer :target_id
      t.string :action_label, null: false
      t.string :action_result, null: false
      t.text :message
      t.datetime :completed_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :owner_task_completion_logs, :completed_at
    add_index :owner_task_completion_logs, [ :target_type, :target_id ]
    add_index :owner_task_completion_logs, :task_type
    add_index :owner_task_completion_logs, :action_result
  end
end

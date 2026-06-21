class CreateAicooExecutorTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_executor_tasks do |t|
      t.string :title, null: false
      t.string :source_type, null: false
      t.integer :source_id, null: false
      t.string :execution_type, null: false
      t.text :execution_prompt
      t.integer :estimated_minutes
      t.string :status, null: false, default: "draft"
      t.datetime :approved_at
      t.datetime :done_at

      t.timestamps
    end

    add_index :aicoo_executor_tasks, %i[source_type source_id]
    add_index :aicoo_executor_tasks, :execution_type
    add_index :aicoo_executor_tasks, :status
    add_index :aicoo_executor_tasks, :approved_at
    add_index :aicoo_executor_tasks, :done_at
  end
end

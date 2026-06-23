class CreateActionExecutionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :action_execution_logs do |t|
      t.references :action_candidate, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.integer :user_id
      t.references :action_result, foreign_key: true
      t.references :revenue_event, foreign_key: true
      t.text :planned_action, null: false
      t.decimal :planned_quantity
      t.text :actual_action, null: false
      t.decimal :actual_quantity
      t.decimal :completion_rate
      t.decimal :variance_quantity
      t.text :variance_reason
      t.text :human_note
      t.string :status, null: false, default: "completed"
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :action_execution_logs, :user_id
    add_index :action_execution_logs, :status
    add_index :action_execution_logs, :started_at
    add_index :action_execution_logs, :finished_at
  end
end

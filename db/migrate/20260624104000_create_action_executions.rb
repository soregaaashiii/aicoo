class CreateActionExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :action_executions do |t|
      t.references :action_candidate, null: false, foreign_key: true
      t.string :status, null: false
      t.string :execution_type
      t.text :execution_prompt
      t.text :execution_notes
      t.datetime :started_at
      t.datetime :completed_at
      t.decimal :actual_hours
      t.decimal :actual_cost_yen
      t.text :result_summary
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :action_executions, :status
    add_index :action_executions, :execution_type
  end
end

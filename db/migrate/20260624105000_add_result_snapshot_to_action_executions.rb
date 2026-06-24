class AddResultSnapshotToActionExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :action_executions, :predicted_profit_yen_snapshot, :integer
    add_column :action_executions, :predicted_success_probability_snapshot, :decimal
    add_column :action_executions, :predicted_hours_snapshot, :decimal
    add_column :action_executions, :predicted_cost_yen_snapshot, :integer
    add_column :action_executions, :action_score_snapshot, :decimal

    add_reference :action_results, :action_execution, foreign_key: true, index: false
    add_index :action_results, :action_execution_id, unique: true
  end
end

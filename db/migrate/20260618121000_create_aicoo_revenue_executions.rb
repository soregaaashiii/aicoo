class CreateAicooRevenueExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_revenue_executions do |t|
      t.string :source_type, null: false
      t.integer :source_id, null: false
      t.string :title, null: false
      t.integer :expected_90d_profit_yen
      t.decimal :success_probability
      t.integer :neglect_loss_90d_yen, default: 0, null: false
      t.integer :revenue_total_value_yen
      t.integer :estimated_work_minutes
      t.integer :budget_yen
      t.decimal :revenue_score
      t.string :status, null: false, default: "planned"
      t.datetime :planned_at
      t.datetime :done_at
      t.datetime :skipped_at
      t.text :note

      t.timestamps
    end

    add_index :aicoo_revenue_executions, %i[source_type source_id]
    add_index :aicoo_revenue_executions, :status
    add_index :aicoo_revenue_executions, :planned_at
  end
end

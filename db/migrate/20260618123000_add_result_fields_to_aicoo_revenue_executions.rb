class AddResultFieldsToAicooRevenueExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_revenue_executions, :actual_90d_profit_yen, :integer
    add_column :aicoo_revenue_executions, :measured_at, :datetime
    add_column :aicoo_revenue_executions, :error_rate, :decimal
    add_column :aicoo_revenue_executions, :calibration_score, :decimal
    add_column :aicoo_revenue_executions, :result_note, :text

    add_index :aicoo_revenue_executions, :measured_at
  end
end

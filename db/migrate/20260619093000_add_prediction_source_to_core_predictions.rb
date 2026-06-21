class AddPredictionSourceToCorePredictions < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_lab_predictions, :prediction_source, :string, null: false, default: "lab"
    add_column :aicoo_revenue_executions, :prediction_source, :string, null: false, default: "revenue"

    add_index :aicoo_lab_predictions, :prediction_source
    add_index :aicoo_revenue_executions, :prediction_source
  end
end

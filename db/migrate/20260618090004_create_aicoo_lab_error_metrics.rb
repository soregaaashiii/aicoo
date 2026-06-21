class CreateAicooLabErrorMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_error_metrics do |t|
      t.references :aicoo_lab_experiment, null: false, foreign_key: true
      t.references :aicoo_lab_prediction, null: false, foreign_key: true
      t.references :aicoo_lab_result, null: false, foreign_key: true
      t.decimal :error_rate
      t.decimal :absolute_error
      t.decimal :calibration_score
      t.datetime :calculated_at, null: false

      t.timestamps
    end

    add_index :aicoo_lab_error_metrics, [ :aicoo_lab_prediction_id, :aicoo_lab_result_id ], unique: true, name: "index_lab_error_metrics_on_prediction_and_result"
  end
end

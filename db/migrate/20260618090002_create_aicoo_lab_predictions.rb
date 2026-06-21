class CreateAicooLabPredictions < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_predictions do |t|
      t.references :aicoo_lab_experiment, null: false, foreign_key: true
      t.string :prediction_type, null: false
      t.integer :target_days, null: false
      t.decimal :predicted_value, null: false
      t.string :predicted_value_unit, null: false
      t.decimal :confidence
      t.text :rationale
      t.datetime :predicted_at, null: false

      t.timestamps
    end

    add_index :aicoo_lab_predictions, [ :aicoo_lab_experiment_id, :prediction_type, :target_days ], name: "index_lab_predictions_on_experiment_type_days"
  end
end

class CreateAicooLabResults < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_results do |t|
      t.references :aicoo_lab_experiment, null: false, foreign_key: true
      t.string :result_type, null: false
      t.integer :target_days, null: false
      t.decimal :actual_value, null: false
      t.string :actual_value_unit, null: false
      t.datetime :measured_at, null: false
      t.integer :sample_size
      t.boolean :is_formal_score, default: false, null: false

      t.timestamps
    end

    add_index :aicoo_lab_results, [ :aicoo_lab_experiment_id, :result_type, :target_days ], name: "index_lab_results_on_experiment_type_days"
    add_index :aicoo_lab_results, :is_formal_score
  end
end

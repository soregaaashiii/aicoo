class CreateAicooLabExperimentCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_experiment_candidates do |t|
      t.string :title, null: false
      t.text :description
      t.string :experiment_type, null: false
      t.string :market_category
      t.string :acquisition_channel, null: false
      t.integer :expected_90d_profit_yen
      t.decimal :success_probability
      t.decimal :expected_value_score
      t.decimal :scoring_speed_score
      t.decimal :lab_priority_score
      t.integer :budget_yen
      t.integer :estimated_work_minutes
      t.integer :assumed_price_yen
      t.integer :lp_word_count
      t.integer :cta_count
      t.integer :development_minutes
      t.integer :feature_count
      t.text :rationale
      t.string :status, default: "proposed", null: false
      t.bigint :converted_experiment_id

      t.timestamps
    end

    add_index :aicoo_lab_experiment_candidates, :status
    add_index :aicoo_lab_experiment_candidates, :experiment_type
    add_index :aicoo_lab_experiment_candidates, :market_category
    add_index :aicoo_lab_experiment_candidates, :acquisition_channel
    add_index :aicoo_lab_experiment_candidates, :lab_priority_score
    add_foreign_key :aicoo_lab_experiment_candidates, :aicoo_lab_experiments, column: :converted_experiment_id
  end
end

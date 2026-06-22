class CreateMetaEvaluationSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :meta_evaluation_snapshots do |t|
      t.date :recorded_on, null: false
      t.references :aicoo_daily_run, foreign_key: true
      t.references :business, foreign_key: true
      t.string :evaluator_type, null: false
      t.integer :average_expected_value_yen, default: 0, null: false
      t.decimal :average_confidence_score, default: 0, null: false
      t.integer :candidate_count, default: 0, null: false
      t.decimal :weighted_contribution_score, default: 0, null: false
      t.text :note

      t.timestamps
    end

    add_index :meta_evaluation_snapshots,
              [ :recorded_on, :business_id, :evaluator_type ],
              unique: true,
              name: "idx_meta_eval_snapshots_unique_date_business_type"
    add_index :meta_evaluation_snapshots,
              [ :recorded_on, :evaluator_type ],
              unique: true,
              where: "business_id IS NULL",
              name: "idx_meta_eval_snapshots_unique_global_type"
  end
end

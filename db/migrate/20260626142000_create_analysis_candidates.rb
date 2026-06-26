class CreateAnalysisCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :analysis_candidates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :analysis_source, null: false
      t.integer :expected_value_yen, default: 0, null: false
      t.decimal :estimated_cost_yen, default: 0, null: false
      t.integer :estimated_minutes, default: 0, null: false
      t.decimal :roi
      t.decimal :confidence, default: 0, null: false
      t.decimal :priority, default: 0, null: false
      t.string :execution_mode, null: false
      t.string :status, default: "pending", null: false
      t.text :reason
      t.jsonb :evidence, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.date :due_on, null: false
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :analysis_candidates, [ :business_id, :analysis_source, :due_on ], unique: true
    add_index :analysis_candidates, :analysis_source
    add_index :analysis_candidates, :execution_mode
    add_index :analysis_candidates, :status
    add_index :analysis_candidates, :due_on
    add_index :analysis_candidates, :priority
  end
end

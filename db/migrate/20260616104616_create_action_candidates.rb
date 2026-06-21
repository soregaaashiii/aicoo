class CreateActionCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :action_candidates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.string :action_type
      t.integer :expected_profit_yen
      t.decimal :expected_hours
      t.integer :expected_hourly_value_yen
      t.integer :cost_yen
      t.decimal :roi
      t.decimal :success_probability
      t.integer :immediate_value_yen
      t.integer :strategic_value_score
      t.integer :risk_reduction_score
      t.decimal :final_score
      t.integer :confidence_score
      t.integer :priority_score
      t.string :status
      t.text :execution_prompt
      t.text :evaluation_reason

      t.timestamps
    end
  end
end

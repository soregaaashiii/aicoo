class CreateBusinessPlaybooks < ActiveRecord::Migration[8.1]
  def change
    create_table :business_playbooks do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.integer :sample_count, null: false, default: 0
      t.decimal :confidence_score, null: false, default: 0
      t.string :top_action_type
      t.string :worst_action_type
      t.string :top_opportunity_type
      t.string :worst_opportunity_type
      t.decimal :average_roi
      t.decimal :average_actual_profit_yen
      t.decimal :average_practicality_score
      t.decimal :average_evidence_score
      t.jsonb :action_type_summary, null: false, default: {}
      t.jsonb :opportunity_type_summary, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_calculated_at

      t.timestamps
    end

    add_column :action_candidates, :business_playbook_score, :decimal
    add_column :opportunity_discovery_items, :business_playbook_score, :decimal
  end
end

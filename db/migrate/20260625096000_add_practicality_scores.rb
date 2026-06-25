class AddPracticalityScores < ActiveRecord::Migration[8.0]
  def change
    add_column :action_candidates, :practicality_score, :decimal
    add_column :action_candidates, :practicality_warning, :boolean, null: false, default: false
    add_column :action_candidates, :practicality_reason, :text
    add_index :action_candidates, :practicality_score

    add_column :opportunity_discovery_items, :practicality_score, :decimal
    add_column :opportunity_discovery_items, :practicality_warning, :boolean, null: false, default: false
    add_column :opportunity_discovery_items, :practicality_reason, :text
    add_index :opportunity_discovery_items, :practicality_score
  end
end

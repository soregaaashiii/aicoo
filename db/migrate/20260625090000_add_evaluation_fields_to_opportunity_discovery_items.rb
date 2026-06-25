class AddEvaluationFieldsToOpportunityDiscoveryItems < ActiveRecord::Migration[8.0]
  def change
    add_reference :opportunity_discovery_items, :source_observation, foreign_key: { to_table: :explore_observations }
    add_column :opportunity_discovery_items, :summary, :text
    add_column :opportunity_discovery_items, :opportunity_type, :string
    add_column :opportunity_discovery_items, :market_signal_score, :decimal
    add_column :opportunity_discovery_items, :urgency_score, :decimal
    add_column :opportunity_discovery_items, :monetization_score, :decimal
    add_column :opportunity_discovery_items, :feasibility_score, :decimal
    add_column :opportunity_discovery_items, :competition_score, :decimal
    add_column :opportunity_discovery_items, :expected_value_yen, :integer
    add_column :opportunity_discovery_items, :confidence, :decimal

    add_index :opportunity_discovery_items, :opportunity_type
    add_index :opportunity_discovery_items, :expected_value_yen
    add_index :opportunity_discovery_items, :confidence
  end
end

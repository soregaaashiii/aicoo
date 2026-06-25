class AddStrategicLearningToOpportunitiesAndDecisionLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :opportunity_discovery_items, :long_term_profit_score, :decimal
    add_column :opportunity_discovery_items, :learning_value_score, :decimal
    add_column :opportunity_discovery_items, :automation_value_score, :decimal
    add_column :opportunity_discovery_items, :exploration_value_score, :decimal
    add_column :opportunity_discovery_items, :strategic_score, :decimal
    add_column :opportunity_discovery_items, :decision_log_coefficient, :decimal, null: false, default: 1.0
    add_column :opportunity_discovery_items, :strategic_adjusted_score, :decimal

    add_column :owner_decision_logs, :generation_source, :string
    add_index :owner_decision_logs, :generation_source
  end
end

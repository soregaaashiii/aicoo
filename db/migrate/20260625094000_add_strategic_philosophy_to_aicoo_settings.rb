class AddStrategicPhilosophyToAicooSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_settings, :long_term_profit_weight, :integer, null: false, default: 45
    add_column :aicoo_settings, :short_term_profit_weight, :integer, null: false, default: 25
    add_column :aicoo_settings, :learning_weight, :integer, null: false, default: 15
    add_column :aicoo_settings, :automation_weight, :integer, null: false, default: 10
    add_column :aicoo_settings, :exploration_weight, :integer, null: false, default: 5
  end
end

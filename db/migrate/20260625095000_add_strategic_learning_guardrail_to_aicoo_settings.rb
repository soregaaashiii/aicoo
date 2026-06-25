class AddStrategicLearningGuardrailToAicooSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_settings, :strategic_learning_enabled, :boolean, null: false, default: true
    add_column :aicoo_settings, :strategic_learning_max_boost_rate, :decimal, null: false, default: 0.25
    add_column :aicoo_settings, :strategic_learning_max_penalty_rate, :decimal, null: false, default: 0.20
    add_column :aicoo_settings, :strategic_learning_warning_threshold_rate, :decimal, null: false, default: 0.15
    add_column :aicoo_settings, :strategic_learning_decision_log_min_count, :integer, null: false, default: 10
  end
end

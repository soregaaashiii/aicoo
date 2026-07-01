class CreateResourceAwareAutoBuilder < ActiveRecord::Migration[7.2]
  def change
    create_table :aicoo_resource_budgets do |t|
      t.integer :codex_concurrent_limit, null: false, default: 1
      t.integer :codex_waiting_limit, null: false, default: 5
      t.integer :build_queue_limit, null: false, default: 5
      t.integer :deploy_queue_limit, null: false, default: 2
      t.integer :render_service_limit, null: false, default: 3
      t.decimal :monthly_ai_budget_yen, precision: 12, scale: 2, null: false, default: 0
      t.decimal :current_month_ai_spend_yen, precision: 12, scale: 2, null: false, default: 0
      t.integer :simultaneous_mvp_limit, null: false, default: 1
      t.boolean :auto_build_enabled, null: false, default: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_column :businesses, :auto_build_enabled, :boolean, null: false, default: false
    add_column :businesses, :auto_build_requires_approval, :boolean, null: false, default: true
    add_column :businesses, :auto_build_risk_level, :string, null: false, default: "low"
    add_index :businesses, :auto_build_enabled
    add_index :businesses, :auto_build_risk_level

    create_table :auto_build_tasks do |t|
      t.references :business, null: false, foreign_key: true
      t.references :aicoo_daily_run, null: true, foreign_key: true
      t.references :auto_revision_task, null: true, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :build_strategy, null: false
      t.string :risk_level, null: false, default: "low"
      t.decimal :priority_score, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_value_yen, precision: 12, scale: 2, null: false, default: 0
      t.decimal :learning_value_score, precision: 8, scale: 2, null: false, default: 0
      t.decimal :estimated_cost_yen, precision: 12, scale: 2, null: false, default: 0
      t.decimal :estimated_build_hours, precision: 8, scale: 2, null: false, default: 0
      t.text :reason
      t.text :codex_prompt
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auto_build_tasks, :status
    add_index :auto_build_tasks, :build_strategy
    add_index :auto_build_tasks, :risk_level
    add_index :auto_build_tasks, :priority_score
    add_index :auto_build_tasks, [ :business_id, :status ]
  end
end

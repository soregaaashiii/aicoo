class CreateDataSourceCostProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :data_source_cost_profiles do |t|
      t.string :source_key, null: false
      t.string :name, null: false
      t.boolean :enabled, default: true, null: false
      t.string :execution_mode, default: "auto", null: false
      t.text :api_key
      t.integer :monthly_budget_yen, default: 0, null: false
      t.integer :monthly_spend_yen, default: 0, null: false
      t.integer :monthly_run_count, default: 0, null: false
      t.decimal :average_cost_yen, default: 0, null: false
      t.decimal :average_expected_profit_yen, default: 0, null: false
      t.datetime :last_run_at
      t.text :last_error
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
    add_index :data_source_cost_profiles, :source_key, unique: true
    add_index :data_source_cost_profiles, :execution_mode
    add_index :data_source_cost_profiles, :enabled
  end
end

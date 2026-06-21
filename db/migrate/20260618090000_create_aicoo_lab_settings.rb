class CreateAicooLabSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_settings do |t|
      t.integer :monthly_budget_yen, default: 5_000, null: false
      t.integer :minimum_sample_pv, default: 1_000, null: false
      t.integer :hourly_cost_yen, default: 1_226, null: false
      t.boolean :auto_generate_enabled, default: true, null: false
      t.boolean :free_experiments_continue_after_budget, default: true, null: false

      t.timestamps
    end
  end
end

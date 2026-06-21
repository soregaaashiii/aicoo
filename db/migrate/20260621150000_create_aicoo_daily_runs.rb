class CreateAicooDailyRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :aicoo_daily_runs do |t|
      t.datetime :started_at
      t.datetime :finished_at
      t.string :status, default: "pending", null: false
      t.date :target_date, null: false
      t.integer :business_metrics_imported_count, default: 0, null: false
      t.integer :proxy_weights_adjusted_count, default: 0, null: false
      t.integer :action_candidates_generated_count, default: 0, null: false
      t.integer :action_results_evaluated_count, default: 0, null: false
      t.text :error_message
      t.text :run_log

      t.timestamps
    end

    add_index :aicoo_daily_runs, :target_date
    add_index :aicoo_daily_runs, %i[target_date status]
  end
end

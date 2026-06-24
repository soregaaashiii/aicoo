class CreateAicooDailyRunSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_daily_run_steps do |t|
      t.references :aicoo_daily_run, null: false, foreign_key: true
      t.string :step_name, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.decimal :duration_seconds
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :aicoo_daily_run_steps, :step_name
    add_index :aicoo_daily_run_steps, :status
  end
end

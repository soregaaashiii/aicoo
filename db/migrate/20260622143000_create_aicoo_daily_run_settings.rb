class CreateAicooDailyRunSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :aicoo_daily_run_settings do |t|
      t.boolean :enabled, null: false, default: true
      t.integer :run_hour, null: false, default: 8
      t.integer :run_minute, null: false, default: 0
      t.string :timezone, null: false, default: "Asia/Tokyo"
      t.boolean :catch_up_enabled, null: false, default: true
      t.boolean :retry_until_success, null: false, default: true
      t.integer :max_retry_per_day, null: false, default: 10
      t.datetime :last_checked_at
      t.datetime :last_success_at

      t.timestamps
    end
  end
end

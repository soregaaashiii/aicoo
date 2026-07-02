class CreateTrafficChannelRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :traffic_channel_runs do |t|
      t.references :business, null: true, foreign_key: true
      t.string :channel_key, null: false
      t.string :status, null: false, default: "success"
      t.string :source, null: false, default: "daily_run"
      t.datetime :ran_at, null: false
      t.integer :sessions, null: false, default: 0
      t.integer :clicks, null: false, default: 0
      t.integer :conversions, null: false, default: 0
      t.integer :revenue_yen, null: false, default: 0
      t.integer :cost_yen, null: false, default: 0
      t.decimal :hours_spent, precision: 8, scale: 2, null: false, default: 0
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :traffic_channel_runs, :channel_key
    add_index :traffic_channel_runs, :status
    add_index :traffic_channel_runs, :ran_at
    add_index :traffic_channel_runs, [ :business_id, :channel_key, :ran_at ], name: "idx_traffic_runs_business_channel_ran_at"
  end
end

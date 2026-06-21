class CreateProxyScoreWeightAdjustmentLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :proxy_score_weight_adjustment_logs do |t|
      t.references :proxy_score_weight, null: false, foreign_key: true
      t.references :business, null: true, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.jsonb :before_weights, default: {}, null: false
      t.jsonb :after_weights, default: {}, null: false
      t.integer :confidence_score, default: 0, null: false
      t.integer :sample_days_count, default: 0, null: false
      t.integer :revenue_events_count, default: 0, null: false
      t.decimal :adjustment_rate, precision: 10, scale: 6, default: "0.0", null: false
      t.text :reason, null: false
      t.datetime :adjusted_at, null: false

      t.timestamps
    end

    add_index :proxy_score_weight_adjustment_logs, :adjusted_at
    add_index :proxy_score_weight_adjustment_logs, [ :business_id, :adjusted_at ], name: "index_proxy_weight_logs_on_business_and_adjusted_at"
  end
end

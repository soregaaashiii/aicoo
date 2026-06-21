class CreateActionResults < ActiveRecord::Migration[8.1]
  def change
    create_table :action_results do |t|
      t.references :action_candidate, null: false, foreign_key: true, index: { unique: true }
      t.references :business, null: false, foreign_key: true
      t.date :executed_on, null: false
      t.date :evaluated_on, null: false
      t.integer :predicted_value_yen
      t.decimal :predicted_success_probability
      t.integer :predicted_expected_profit_yen
      t.integer :actual_revenue_yen, default: 0, null: false
      t.integer :actual_profit_yen, default: 0, null: false
      t.decimal :actual_proxy_score_delta, default: "0.0", null: false
      t.integer :actual_impressions_delta, default: 0, null: false
      t.integer :actual_clicks_delta, default: 0, null: false
      t.integer :actual_sessions_delta, default: 0, null: false
      t.integer :actual_pageviews_delta, default: 0, null: false
      t.integer :actual_phone_clicks_delta, default: 0, null: false
      t.integer :actual_map_clicks_delta, default: 0, null: false
      t.integer :actual_affiliate_clicks_delta, default: 0, null: false
      t.integer :prediction_error_yen
      t.decimal :prediction_error_rate
      t.string :evaluation_status, default: "pending", null: false
      t.text :note

      t.timestamps
    end

    add_index :action_results, :evaluation_status
    add_index :action_results, :evaluated_on
  end
end

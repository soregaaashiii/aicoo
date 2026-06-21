class CreateProxyScoreWeights < ActiveRecord::Migration[8.1]
  def change
    create_table :proxy_score_weights do |t|
      t.references :business, null: true, foreign_key: true
      t.decimal :impressions_weight, precision: 12, scale: 4, default: "0.01", null: false
      t.decimal :clicks_weight, precision: 12, scale: 4, default: "1.0", null: false
      t.decimal :sessions_weight, precision: 12, scale: 4, default: "1.0", null: false
      t.decimal :pageviews_weight, precision: 12, scale: 4, default: "0.5", null: false
      t.decimal :phone_clicks_weight, precision: 12, scale: 4, default: "10.0", null: false
      t.decimal :map_clicks_weight, precision: 12, scale: 4, default: "8.0", null: false
      t.decimal :affiliate_clicks_weight, precision: 12, scale: 4, default: "20.0", null: false
      t.string :source_type, default: "default", null: false
      t.integer :confidence_score, default: 0, null: false
      t.datetime :adjusted_at
      t.text :note

      t.timestamps
    end

    add_index :proxy_score_weights, :source_type
  end
end

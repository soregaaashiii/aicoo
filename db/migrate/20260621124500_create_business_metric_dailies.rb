class CreateBusinessMetricDailies < ActiveRecord::Migration[8.1]
  def change
    create_table :business_metric_dailies do |t|
      t.references :business, null: false, foreign_key: true
      t.date :recorded_on, null: false
      t.integer :impressions, default: 0, null: false
      t.integer :clicks, default: 0, null: false
      t.integer :sessions, default: 0, null: false
      t.integer :pageviews, default: 0, null: false
      t.integer :phone_clicks, default: 0, null: false
      t.integer :map_clicks, default: 0, null: false
      t.integer :affiliate_clicks, default: 0, null: false

      t.timestamps
    end

    add_index :business_metric_dailies, :recorded_on
    add_index :business_metric_dailies, [ :business_id, :recorded_on ]
  end
end

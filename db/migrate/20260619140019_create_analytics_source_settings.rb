class CreateAnalyticsSourceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_source_settings do |t|
      t.string :source_type, null: false
      t.string :name, null: false
      t.string :property_id
      t.string :site_url
      t.boolean :enabled, default: true, null: false
      t.text :credentials_json
      t.text :refresh_token
      t.datetime :last_fetched_at
      t.integer :fetch_days, default: 28, null: false

      t.timestamps
    end

    add_index :analytics_source_settings, :source_type
  end
end

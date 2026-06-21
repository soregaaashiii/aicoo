class CreateAicooAnalyticsSites < ActiveRecord::Migration[8.1]
  def change
    create_table :aicoo_analytics_sites do |t|
      t.string :name, null: false
      t.references :business, foreign_key: true, null: true
      t.string :public_url
      t.string :domain
      t.string :gsc_site_url
      t.string :ga4_property_id
      t.boolean :enabled, null: false, default: true
      t.text :notes
      t.datetime :last_gsc_fetch_at
      t.datetime :last_ga4_fetch_at

      t.timestamps
    end

    add_index :aicoo_analytics_sites, :domain
    add_index :aicoo_analytics_sites, :gsc_site_url
    add_index :aicoo_analytics_sites, :ga4_property_id
  end
end

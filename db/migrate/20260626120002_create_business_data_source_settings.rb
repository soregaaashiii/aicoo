class CreateBusinessDataSourceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :business_data_source_settings do |t|
      t.references :business, null: false, foreign_key: true
      t.string :source_key, null: false
      t.boolean :enabled, default: true, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
    add_index :business_data_source_settings, [ :business_id, :source_key ], unique: true
    add_index :business_data_source_settings, :source_key
    add_index :business_data_source_settings, :enabled
  end
end

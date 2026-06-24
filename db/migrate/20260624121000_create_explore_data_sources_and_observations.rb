class CreateExploreDataSourcesAndObservations < ActiveRecord::Migration[8.0]
  def change
    create_table :explore_data_sources do |t|
      t.string :name, null: false
      t.string :source_type, null: false
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: "inactive"
      t.datetime :last_sync_at
      t.datetime :last_success_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :explore_data_sources, :source_type
    add_index :explore_data_sources, :status
    add_index :explore_data_sources, :enabled

    create_table :explore_observations do |t|
      t.references :explore_data_source, null: false, foreign_key: true
      t.references :opportunity_discovery_item, null: true, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :observation_type, null: false
      t.decimal :score
      t.datetime :observed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :explore_observations, :observation_type
    add_index :explore_observations, :score
    add_index :explore_observations, :observed_at
  end
end

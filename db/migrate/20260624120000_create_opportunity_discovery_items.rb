class CreateOpportunityDiscoveryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :opportunity_discovery_items do |t|
      t.string :title, null: false
      t.text :description
      t.string :source_type, null: false
      t.decimal :opportunity_score
      t.string :status, null: false
      t.datetime :discovered_at
      t.references :business, foreign_key: true
      t.references :action_candidate, foreign_key: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :opportunity_discovery_items, :source_type
    add_index :opportunity_discovery_items, :status
    add_index :opportunity_discovery_items, :discovered_at
  end
end

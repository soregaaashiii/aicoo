class CreateSourceAppDiffTables < ActiveRecord::Migration[8.0]
  def change
    create_table :source_app_connections do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source_app, null: false
      t.string :connection_type, null: false, default: "same_database"
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: "active"
      t.datetime :last_checked_at
      t.datetime :last_success_at
      t.text :last_error
      t.jsonb :settings, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :source_app_connections, [ :business_id, :source_app ], unique: true
    add_index :source_app_connections, :enabled
    add_index :source_app_connections, :status

    create_table :source_app_diff_rules do |t|
      t.references :source_app_connection, null: false, foreign_key: true
      t.string :name, null: false
      t.string :watched_table, null: false
      t.string :resource_type, null: false
      t.string :activity_type, null: false
      t.jsonb :watched_fields, null: false, default: []
      t.jsonb :metadata_fields, null: false, default: []
      t.string :title_template
      t.integer :estimated_work_seconds
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :source_app_diff_rules, [ :source_app_connection_id, :name ], unique: true
    add_index :source_app_diff_rules, :watched_table
    add_index :source_app_diff_rules, :enabled

    create_table :source_app_diff_cursors do |t|
      t.references :source_app_diff_rule, null: false, foreign_key: true, index: { unique: true }
      t.datetime :last_checked_at
      t.bigint :last_seen_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end

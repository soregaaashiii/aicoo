class CreateExploreImportLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :explore_import_logs do |t|
      t.string :source_type, null: false
      t.string :import_format, null: false
      t.integer :imported_count, null: false, default: 0

      t.timestamps
    end

    add_index :explore_import_logs, :source_type
    add_index :explore_import_logs, :import_format
    add_index :explore_import_logs, :created_at
  end
end

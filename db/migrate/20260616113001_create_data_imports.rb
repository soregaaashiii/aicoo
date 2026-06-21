class CreateDataImports < ActiveRecord::Migration[8.1]
  def change
    create_table :data_imports do |t|
      t.references :data_source, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :content_type
      t.integer :row_count
      t.text :raw_text
      t.text :processed_text
      t.datetime :imported_at, null: false

      t.timestamps
    end
  end
end

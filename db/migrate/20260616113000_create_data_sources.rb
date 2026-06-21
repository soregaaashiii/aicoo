class CreateDataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :data_sources do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source_type, null: false
      t.string :status, null: false, default: "active"
      t.text :notes

      t.timestamps
    end
  end
end

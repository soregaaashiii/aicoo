class CreateAicooDataSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_data_snapshots do |t|
      t.string :source_type, null: false
      t.integer :source_id, null: false
      t.datetime :captured_at, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :aicoo_data_snapshots, :source_type
    add_index :aicoo_data_snapshots, [ :source_type, :source_id ]
    add_index :aicoo_data_snapshots, :captured_at
  end
end

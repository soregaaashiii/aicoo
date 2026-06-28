class CreateGoogleApiImportRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :google_api_import_runs do |t|
      t.references :business, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.jsonb :source_types, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.decimal :duration_seconds, precision: 10, scale: 2
      t.integer :fetched_days, null: false, default: 28
      t.integer :updated_metric_count, null: false, default: 0
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :google_api_import_runs, :status
    add_index :google_api_import_runs, [ :business_id, :status ]
    add_index :google_api_import_runs, [ :business_id, :created_at ]
  end
end

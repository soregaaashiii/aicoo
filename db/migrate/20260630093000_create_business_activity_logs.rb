class CreateBusinessActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :business_activity_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.string :source_app, null: false
      t.string :activity_type, null: false
      t.string :resource_type, null: false
      t.string :resource_id, null: false
      t.string :title, null: false
      t.datetime :occurred_at, null: false
      t.datetime :detected_at, null: false
      t.jsonb :changed_fields, null: false, default: {}
      t.jsonb :before_snapshot, null: false, default: {}
      t.jsonb :after_snapshot, null: false, default: {}
      t.text :diff_summary
      t.jsonb :metadata, null: false, default: {}
      t.integer :estimated_work_seconds
      t.string :source_method, null: false, default: "logger"
      t.string :idempotency_key, null: false
      t.string :evaluation_status, null: false, default: "pending"

      t.timestamps
    end

    add_index :business_activity_logs, [ :business_id, :idempotency_key ], unique: true
    add_index :business_activity_logs, [ :business_id, :occurred_at ]
    add_index :business_activity_logs, :activity_type
    add_index :business_activity_logs, :evaluation_status
  end
end

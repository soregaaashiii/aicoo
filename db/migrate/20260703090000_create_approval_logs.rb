class CreateApprovalLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :approval_logs do |t|
      t.string :approvable_type, null: false
      t.bigint :approvable_id, null: false
      t.references :business, null: true, foreign_key: true
      t.string :action, null: false
      t.string :operator
      t.string :source, null: false, default: "unknown"
      t.string :previous_status
      t.string :new_status
      t.string :common_previous_status
      t.string :common_new_status
      t.boolean :idempotent, null: false, default: false
      t.text :message
      t.jsonb :metadata, null: false, default: {}
      t.datetime :approved_at, null: false

      t.timestamps
    end

    add_index :approval_logs, [ :approvable_type, :approvable_id ]
    add_index :approval_logs, :action
    add_index :approval_logs, :source
    add_index :approval_logs, :approved_at
  end
end

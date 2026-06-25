class CreateOwnerDecisionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :owner_decision_logs do |t|
      t.string :subject_type, null: false
      t.integer :subject_id, null: false
      t.references :queue_item, foreign_key: { to_table: :owner_execution_queue_items }
      t.references :business, foreign_key: true
      t.string :decision_type, null: false
      t.string :decision_source, null: false
      t.string :title
      t.integer :expected_value_yen
      t.decimal :confidence
      t.string :risk_level
      t.string :action_type
      t.string :opportunity_type
      t.string :previous_status
      t.string :new_status
      t.text :reason
      t.datetime :decided_at, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :owner_decision_logs, %i[subject_type subject_id]
    add_index :owner_decision_logs, :decision_type
    add_index :owner_decision_logs, :decision_source
    add_index :owner_decision_logs, :decided_at
    add_index :owner_decision_logs, :risk_level
    add_index :owner_decision_logs, :action_type
  end
end

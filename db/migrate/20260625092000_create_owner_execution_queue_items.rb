class CreateOwnerExecutionQueueItems < ActiveRecord::Migration[8.0]
  def change
    change_table :aicoo_settings do |t|
      t.integer :daily_owner_queue_limit, default: 10, null: false
      t.boolean :auto_queue_low_risk_enabled, default: true, null: false
      t.boolean :auto_queue_medium_risk_enabled, default: true, null: false
      t.boolean :auto_queue_high_risk_enabled, default: false, null: false
    end

    create_table :owner_execution_queue_items do |t|
      t.string :item_type, null: false
      t.integer :item_id, null: false
      t.references :business, foreign_key: true
      t.string :title, null: false
      t.decimal :priority_score
      t.integer :expected_value_yen
      t.string :risk_level, null: false, default: "medium"
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.date :due_on, null: false
      t.string :generated_from
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :owner_execution_queue_items, %i[item_type item_id due_on], unique: true
    add_index :owner_execution_queue_items, :risk_level
    add_index :owner_execution_queue_items, :status
    add_index :owner_execution_queue_items, :due_on
  end
end

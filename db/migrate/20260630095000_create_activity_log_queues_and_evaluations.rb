class CreateActivityLogQueuesAndEvaluations < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_activity_log_queues do |t|
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempted_at
      t.datetime :next_retry_at
      t.text :error_message
      t.string :idempotency_key
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :aicoo_activity_log_queues, :status
    add_index :aicoo_activity_log_queues, :next_retry_at
    add_index :aicoo_activity_log_queues, :idempotency_key

    create_table :activity_evaluations do |t|
      t.references :business_activity_log, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.integer :evaluation_window_days, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :baseline_snapshot, null: false, default: {}
      t.jsonb :result_snapshot, null: false, default: {}
      t.jsonb :metric_deltas, null: false, default: {}
      t.datetime :evaluated_at
      t.text :skip_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :activity_evaluations,
              [ :business_activity_log_id, :evaluation_window_days ],
              unique: true,
              name: "index_activity_evaluations_on_log_and_window"
    add_index :activity_evaluations, :status
  end
end

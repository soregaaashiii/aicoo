class CreatePipelineRecoveryLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_recovery_logs do |t|
      t.references :aicoo_pipeline_run, null: false, foreign_key: true
      t.references :business, null: true, foreign_key: true
      t.string :stage, null: false
      t.string :stuck_reason, null: false
      t.string :action, null: false
      t.string :before_status
      t.string :after_status
      t.boolean :success, null: false, default: false
      t.text :error_message
      t.datetime :executed_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pipeline_recovery_logs, :stage
    add_index :pipeline_recovery_logs, :stuck_reason
    add_index :pipeline_recovery_logs, :action
    add_index :pipeline_recovery_logs, :success
    add_index :pipeline_recovery_logs, :executed_at
  end
end

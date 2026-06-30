class AddStuckDetectionToAicooPipelineRuns < ActiveRecord::Migration[8.0]
  def change
    change_table :aicoo_pipeline_runs, bulk: true do |t|
      t.boolean :stuck, null: false, default: false
      t.string :stuck_reason
      t.datetime :stuck_detected_at
      t.boolean :auto_recoverable, null: false, default: false
      t.string :recovery_action
      t.text :recovery_message
    end

    add_index :aicoo_pipeline_runs, :stuck
    add_index :aicoo_pipeline_runs, :stuck_reason
    add_index :aicoo_pipeline_runs, :stuck_detected_at
  end
end

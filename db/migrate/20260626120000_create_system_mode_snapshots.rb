class CreateSystemModeSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :system_mode_snapshots do |t|
      t.datetime :captured_at, null: false
      t.decimal :health_score, default: 0, null: false
      t.integer :warning_count, default: 0, null: false
      t.integer :critical_count, default: 0, null: false
      t.jsonb :pipeline_status, default: {}, null: false
      t.jsonb :integrations_summary, default: {}, null: false
      t.jsonb :jobs_summary, default: {}, null: false
      t.jsonb :queues_summary, default: {}, null: false
      t.jsonb :learning_summary, default: {}, null: false
      t.jsonb :playbook_summary, default: {}, null: false
      t.jsonb :executor_summary, default: {}, null: false
      t.jsonb :settings_summary, default: {}, null: false
      t.jsonb :visual_analytics, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :system_mode_snapshots, :captured_at
  end
end

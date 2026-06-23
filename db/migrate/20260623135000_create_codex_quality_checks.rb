class CreateCodexQualityChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :codex_quality_checks do |t|
      t.references :auto_revision_task, null: false, foreign_key: true, index: { unique: true }
      t.integer :quality_score, null: false, default: 0
      t.integer :risk_score, null: false, default: 0
      t.string :test_status, null: false, default: "unknown"
      t.boolean :migration_detected, null: false, default: false
      t.boolean :high_risk_change_detected, null: false, default: false
      t.integer :changed_files_count, null: false, default: 0
      t.integer :warning_count, null: false, default: 0
      t.jsonb :warnings, null: false, default: []
      t.string :result, null: false, default: "review_required"

      t.timestamps
    end

    add_index :codex_quality_checks, :result
    add_index :codex_quality_checks, :test_status
  end
end

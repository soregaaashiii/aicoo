class AddQualityGateFieldsToCodexQualityChecks < ActiveRecord::Migration[8.0]
  def change
    add_column :codex_quality_checks, :approval_status, :string, null: false, default: "pending"
    add_column :codex_quality_checks, :approved_at, :datetime
    add_column :codex_quality_checks, :approved_by, :string
    add_column :codex_quality_checks, :approval_note, :text

    add_index :codex_quality_checks, :approval_status
    add_index :codex_quality_checks, :approved_at
  end
end

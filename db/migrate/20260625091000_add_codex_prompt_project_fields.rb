class AddCodexPromptProjectFields < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :project_key, :string
    add_column :businesses, :local_project_path, :string
    add_column :businesses, :repository_name, :string
    add_column :businesses, :default_verification_commands, :jsonb, null: false, default: []

    add_index :businesses, :project_key

    create_table :codex_prompt_drafts do |t|
      t.references :action_candidate, null: false, foreign_key: true
      t.references :business, foreign_key: true
      t.string :project_key
      t.string :local_project_path
      t.string :title, null: false
      t.text :objective
      t.text :prompt_body
      t.string :risk_level, null: false, default: "medium"
      t.string :status, null: false, default: "draft"
      t.string :generated_from
      t.text :safety_notes
      t.jsonb :verification_commands, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :codex_prompt_drafts, :project_key
    add_index :codex_prompt_drafts, :risk_level
    add_index :codex_prompt_drafts, :status
  end
end

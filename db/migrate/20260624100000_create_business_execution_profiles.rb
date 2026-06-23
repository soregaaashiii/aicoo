class CreateBusinessExecutionProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :business_execution_profiles do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.string :repository_name
      t.string :repository_type, null: false, default: "other"
      t.string :repository_path
      t.string :github_repository
      t.string :default_branch, null: false, default: "main"
      t.text :test_command
      t.text :lint_command
      t.text :deploy_command
      t.string :production_url
      t.text :codex_instructions
      t.text :forbidden_patterns
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end

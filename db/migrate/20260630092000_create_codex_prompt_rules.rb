class CreateCodexPromptRules < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_prompt_rules do |t|
      t.string :name, null: false
      t.string :scope, null: false
      t.references :business, foreign_key: true
      t.string :rule_category, null: false
      t.text :content, null: false
      t.boolean :active, null: false, default: true
      t.integer :priority, null: false, default: 100

      t.timestamps
    end

    add_index :codex_prompt_rules, :scope
    add_index :codex_prompt_rules, :rule_category
    add_index :codex_prompt_rules, :active
    add_index :codex_prompt_rules, [ :scope, :business_id, :rule_category, :priority ], name: "idx_codex_prompt_rules_lookup"
    add_index :codex_prompt_rules, [ :name, :scope, :business_id ], unique: true
  end
end

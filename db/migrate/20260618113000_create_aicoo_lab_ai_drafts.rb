class CreateAicooLabAiDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_ai_drafts do |t|
      t.string :title, null: false
      t.references :generation_run, null: false, foreign_key: { to_table: :aicoo_lab_generation_runs }
      t.text :raw_response
      t.jsonb :parsed_json, default: {}, null: false
      t.string :status, null: false
      t.datetime :approved_at
      t.datetime :imported_at

      t.timestamps
    end

    add_index :aicoo_lab_ai_drafts, :status
    add_index :aicoo_lab_ai_drafts, :created_at
  end
end

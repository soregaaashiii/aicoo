class CreateAutoRevisionTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :auto_revision_tasks do |t|
      t.references :action_candidate, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :title, null: false
      t.text :execution_prompt
      t.string :risk_level, null: false, default: "medium"
      t.string :status, null: false, default: "draft"
      t.decimal :priority_score, precision: 12, scale: 2, null: false, default: 0
      t.string :generated_by, null: false, default: "aicoo"
      t.datetime :approved_at
      t.datetime :started_at
      t.datetime :finished_at
      t.text :result_summary
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auto_revision_tasks, :risk_level
    add_index :auto_revision_tasks, :status
    add_index :auto_revision_tasks, :generated_by
    add_index :auto_revision_tasks, :priority_score
  end
end

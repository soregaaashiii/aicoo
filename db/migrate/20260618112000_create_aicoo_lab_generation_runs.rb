class CreateAicooLabGenerationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_generation_runs do |t|
      t.string :generation_type, null: false
      t.text :prompt
      t.text :response
      t.string :status, null: false
      t.integer :generated_count, default: 0, null: false
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :aicoo_lab_generation_runs, :generation_type
    add_index :aicoo_lab_generation_runs, :status
    add_index :aicoo_lab_generation_runs, :created_at
  end
end

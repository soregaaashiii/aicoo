class CreateAicooInsightGenerationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_insight_generation_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: "running"
      t.integer :generated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.text :error_message
      t.string :source, null: false, default: "manual"

      t.timestamps
    end

    add_index :aicoo_insight_generation_runs, :started_at
    add_index :aicoo_insight_generation_runs, :status
    add_index :aicoo_insight_generation_runs, :source
  end
end

class CreateSerpRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :serp_runs do |t|
      t.string :status, null: false, default: "running"
      t.datetime :started_at
      t.datetime :finished_at
      t.string :executed_by, null: false, default: "manual"
      t.integer :query_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.integer :candidate_count, null: false, default: 0
      t.integer :credit_estimate, null: false, default: 0
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :serp_runs, :status
    add_index :serp_runs, :executed_by
    add_index :serp_runs, :started_at

    add_reference :serp_analyses, :serp_run, foreign_key: true
  end
end

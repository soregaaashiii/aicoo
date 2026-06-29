class CreateAicooPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :aicoo_pipeline_runs do |t|
      t.references :business, foreign_key: true
      t.references :idea_pipeline_item, foreign_key: true
      t.references :aicoo_lab_landing_page, foreign_key: true
      t.string :pipeline_type, null: false, default: "idea_pipeline"
      t.string :status, null: false, default: "running"
      t.string :current_stage, null: false, default: "discovery"
      t.string :next_stage
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :retry_count, null: false, default: 0
      t.text :last_error
      t.decimal :confidence
      t.decimal :expected_value_yen
      t.decimal :estimated_cost_yen
      t.decimal :actual_cost_yen
      t.datetime :waiting_until
      t.string :waiting_reason
      t.string :halted_reason
      t.string :pivot_decision
      t.jsonb :stage_states, null: false, default: {}
      t.jsonb :gate_snapshot, null: false, default: {}
      t.jsonb :retry_schedule, null: false, default: {}
      t.jsonb :budget_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :aicoo_pipeline_runs, :pipeline_type
    add_index :aicoo_pipeline_runs, :status
    add_index :aicoo_pipeline_runs, :current_stage
    add_index :aicoo_pipeline_runs, :next_stage
    add_index :aicoo_pipeline_runs, :waiting_until
    add_index :aicoo_pipeline_runs, :pivot_decision
    add_index :aicoo_pipeline_runs, [ :pipeline_type, :idea_pipeline_item_id ], unique: true, name: "idx_pipeline_runs_on_type_and_idea_item"
  end
end

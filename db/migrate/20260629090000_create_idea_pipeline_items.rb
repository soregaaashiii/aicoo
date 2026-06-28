class CreateIdeaPipelineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :idea_pipeline_items do |t|
      t.references :business, foreign_key: true
      t.references :aicoo_lab_experiment, foreign_key: true
      t.references :aicoo_lab_landing_page, foreign_key: true
      t.string :title, null: false
      t.text :short_description
      t.text :problem
      t.text :target_user
      t.text :revenue_model
      t.text :mvp_concept
      t.text :lp_concept
      t.string :status, default: "idea", null: false
      t.string :current_stage, default: "idea", null: false
      t.string :mvp_decision
      t.decimal :difficulty_score
      t.decimal :development_hours
      t.decimal :ai_implementation_score
      t.decimal :market_score
      t.decimal :competition_score
      t.decimal :monetization_score
      t.decimal :automation_score
      t.decimal :serp_difficulty_score
      t.decimal :maintenance_cost_score
      t.integer :expected_profit_yen
      t.decimal :final_score
      t.text :mvp_specification
      t.jsonb :serp_snapshot, default: {}, null: false
      t.jsonb :learning_snapshot, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :evaluated_at
      t.datetime :serp_evaluated_at
      t.datetime :lp_generated_at
      t.datetime :published_at
      t.datetime :learning_evaluated_at
      t.datetime :mvp_decided_at

      t.timestamps
    end

    add_index :idea_pipeline_items, :status
    add_index :idea_pipeline_items, :current_stage
    add_index :idea_pipeline_items, :final_score
    add_index :idea_pipeline_items, :mvp_decision
    add_index :idea_pipeline_items, :created_at
  end
end

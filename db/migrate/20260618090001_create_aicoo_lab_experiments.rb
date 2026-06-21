class CreateAicooLabExperiments < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_experiments do |t|
      t.string :title, null: false
      t.text :description
      t.string :experiment_type, null: false
      t.string :market_category
      t.string :acquisition_channel, null: false
      t.string :status, default: "draft", null: false
      t.string :approval_status, default: "not_required", null: false
      t.string :public_url
      t.string :preview_url
      t.integer :expected_90d_profit_yen
      t.decimal :success_probability
      t.decimal :expected_value_score
      t.decimal :learning_value_score, default: 1.0, null: false
      t.decimal :scoring_speed_score
      t.decimal :lab_priority_score
      t.integer :budget_yen
      t.integer :actual_cost_yen
      t.integer :estimated_work_minutes
      t.integer :actual_work_minutes
      t.datetime :started_at
      t.datetime :published_at
      t.datetime :score_due_7d_at
      t.datetime :score_due_30d_at
      t.datetime :score_due_90d_at
      t.datetime :scored_7d_at
      t.datetime :scored_30d_at
      t.datetime :scored_90d_at
      t.integer :sample_pv_threshold, default: 1_000, null: false
      t.integer :current_pv, default: 0, null: false
      t.string :created_by
      t.text :notes
      t.integer :lp_word_count
      t.integer :cta_count
      t.integer :assumed_price_yen
      t.integer :development_minutes
      t.integer :feature_count

      t.timestamps
    end

    add_index :aicoo_lab_experiments, :status
    add_index :aicoo_lab_experiments, :approval_status
    add_index :aicoo_lab_experiments, :experiment_type
    add_index :aicoo_lab_experiments, :market_category
    add_index :aicoo_lab_experiments, :acquisition_channel
    add_index :aicoo_lab_experiments, :lab_priority_score
  end
end

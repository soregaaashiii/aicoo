class CreateActionCandidateScoreSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :action_candidate_score_snapshots do |t|
      t.references :action_candidate, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.date :recorded_on, null: false
      t.decimal :raw_score, default: 0, null: false
      t.decimal :judge_adjusted_score, default: 0, null: false
      t.decimal :generation_source_accuracy
      t.decimal :action_type_accuracy
      t.decimal :business_error_rate
      t.decimal :adjustment_multiplier, default: 1, null: false
      t.integer :raw_rank, null: false
      t.integer :adjusted_rank, null: false
      t.integer :rank_delta, null: false
      t.text :reason

      t.timestamps
    end

    add_index :action_candidate_score_snapshots,
              [ :action_candidate_id, :recorded_on ],
              unique: true,
              name: "idx_action_score_snapshots_unique_candidate_date"
    add_index :action_candidate_score_snapshots, :recorded_on
    add_index :action_candidate_score_snapshots, :rank_delta
    add_index :action_candidate_score_snapshots, :adjustment_multiplier
  end
end

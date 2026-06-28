class CreateSerpLandingPageCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :serp_landing_page_candidates do |t|
      t.references :serp_analysis, foreign_key: true
      t.references :aicoo_lab_landing_page, foreign_key: true
      t.string :keyword, null: false
      t.string :service_name
      t.string :target_audience
      t.text :problem
      t.string :lp_title
      t.text :lp_description
      t.string :cta_text
      t.decimal :expected_value_score, precision: 10, scale: 2
      t.text :competition_note
      t.string :status, null: false, default: "proposed"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :serp_landing_page_candidates, :keyword
    add_index :serp_landing_page_candidates, :status
    add_index :serp_landing_page_candidates, :expected_value_score
  end
end

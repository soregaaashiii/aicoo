class CreateSerpAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :serp_analyses do |t|
      t.references :business, null: false, foreign_key: true
      t.references :data_import, foreign_key: true
      t.string :keyword, null: false
      t.string :search_engine, null: false, default: "google"
      t.string :location
      t.string :device
      t.integer :result_count
      t.integer :competition_score
      t.text :summary
      t.datetime :analyzed_at, null: false

      t.timestamps
    end
  end
end

class CreateSerpResults < ActiveRecord::Migration[8.1]
  def change
    create_table :serp_results do |t|
      t.references :serp_analysis, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title
      t.string :url
      t.text :snippet

      t.timestamps
    end
  end
end

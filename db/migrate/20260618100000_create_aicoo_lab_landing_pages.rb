class CreateAicooLabLandingPages < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_landing_pages do |t|
      t.references :aicoo_lab_experiment, null: false, foreign_key: true
      t.string :headline
      t.string :subheadline
      t.text :body
      t.string :cta_text
      t.integer :assumed_price_yen
      t.string :status, default: "draft", null: false
      t.string :preview_slug, null: false
      t.string :published_slug
      t.datetime :generated_at
      t.text :notes

      t.timestamps
    end

    add_index :aicoo_lab_landing_pages, :aicoo_lab_experiment_id, unique: true, name: "index_lab_landing_pages_on_experiment_id"
    add_index :aicoo_lab_landing_pages, :preview_slug, unique: true
    add_index :aicoo_lab_landing_pages, :published_slug, unique: true
    add_index :aicoo_lab_landing_pages, :status
  end
end

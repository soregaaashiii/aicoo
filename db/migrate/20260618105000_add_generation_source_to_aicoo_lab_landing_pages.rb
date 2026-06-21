class AddGenerationSourceToAicooLabLandingPages < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_lab_landing_pages, :generation_source, :string, null: false, default: "manual"
    add_index :aicoo_lab_landing_pages, :generation_source
  end
end

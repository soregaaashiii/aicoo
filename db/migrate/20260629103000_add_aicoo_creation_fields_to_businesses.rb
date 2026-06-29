class AddAicooCreationFieldsToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :category, :string
    add_column :businesses, :source, :string
    add_column :businesses, :idea_id, :integer
    add_column :businesses, :created_by_aicoo, :boolean, null: false, default: false
    add_column :businesses, :launched, :boolean, null: false, default: false
    add_column :businesses, :daily_run_enabled, :boolean, null: false, default: true
    add_column :businesses, :serp_enabled, :boolean, null: false, default: true

    add_index :businesses, :created_by_aicoo
    add_index :businesses, :idea_id
    add_index :businesses, :launched
  end
end

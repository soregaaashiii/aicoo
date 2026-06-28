class AddAdapterFieldsToSerpAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :serp_analyses, :provider, :string, null: false, default: "manual"
    add_column :serp_analyses, :status, :string, null: false, default: "success"
    add_column :serp_analyses, :error_message, :text
    add_column :serp_analyses, :raw_summary, :jsonb, null: false, default: {}

    add_index :serp_analyses, :provider
    add_index :serp_analyses, :status
  end
end

class AddAutolinkFieldsToAicooAnalyticsSites < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_analytics_sites, :auto_created, :boolean, default: false, null: false
    add_column :aicoo_analytics_sites, :autolink_source_type, :string
    add_column :aicoo_analytics_sites, :autolink_source_id, :integer
    add_index :aicoo_analytics_sites, :auto_created
    add_index :aicoo_analytics_sites, [ :autolink_source_type, :autolink_source_id ], name: "idx_analytics_sites_on_autolink_source"
  end
end

class AddAnalyticsSiteReferences < ActiveRecord::Migration[8.1]
  def change
    add_reference :analytics_source_settings, :aicoo_analytics_site, foreign_key: true, null: true
    add_reference :data_imports, :aicoo_analytics_site, foreign_key: true, null: true
  end
end

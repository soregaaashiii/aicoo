class ChangeAnalyticsSourceSettingsClientIdToText < ActiveRecord::Migration[8.1]
  def change
    change_column :analytics_source_settings, :client_id, :text
  end
end

class AddGoogleClientCredentialsToAnalyticsSourceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_source_settings, :client_id, :string
    add_column :analytics_source_settings, :client_secret, :text
  end
end

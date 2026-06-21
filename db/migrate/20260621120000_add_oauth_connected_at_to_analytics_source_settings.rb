class AddOauthConnectedAtToAnalyticsSourceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_source_settings, :oauth_connected_at, :datetime
  end
end

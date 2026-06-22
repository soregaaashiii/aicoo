class AddAuthenticationModeToAnalytics < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_analytics_sites, :authentication_mode, :string, default: "shared", null: false
    add_column :analytics_source_settings, :authentication_mode, :string, default: "shared", null: false
    add_index :aicoo_analytics_sites, :authentication_mode
    add_index :analytics_source_settings, :authentication_mode

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE analytics_source_settings
          SET authentication_mode = 'individual'
          WHERE client_id IS NOT NULL
            AND client_id <> ''
            AND client_secret IS NOT NULL
            AND client_secret <> ''
            AND refresh_token IS NOT NULL
            AND refresh_token <> ''
        SQL
      end
    end
  end
end

class CreateAicooGoogleCredentials < ActiveRecord::Migration[8.1]
  class MigrationAnalyticsSourceSetting < ActiveRecord::Base
    self.table_name = "analytics_source_settings"
  end

  class MigrationAicooGoogleCredential < ActiveRecord::Base
    self.table_name = "aicoo_google_credentials"
  end

  def up
    create_table :aicoo_google_credentials do |t|
      t.string :name, null: false
      t.text :client_id
      t.text :client_secret
      t.text :refresh_token
      t.boolean :enabled, default: true, null: false
      t.datetime :connected_at
      t.text :notes

      t.timestamps
    end

    add_index :aicoo_google_credentials, :enabled
    add_reference :analytics_source_settings, :google_credential, foreign_key: { to_table: :aicoo_google_credentials }

    migrate_existing_analytics_credentials
  end

  def down
    remove_reference :analytics_source_settings, :google_credential, foreign_key: { to_table: :aicoo_google_credentials }
    drop_table :aicoo_google_credentials
  end

  private

  def migrate_existing_analytics_credentials
    source = MigrationAnalyticsSourceSetting
             .where.not(client_id: [ nil, "" ])
             .where.not(client_secret: [ nil, "" ])
             .where.not(refresh_token: [ nil, "" ])
             .order(:created_at)
             .first
    return unless source

    credential = MigrationAicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: source.client_id,
      client_secret: source.client_secret,
      refresh_token: source.refresh_token,
      enabled: true,
      connected_at: source.oauth_connected_at || Time.current,
      created_at: Time.current,
      updated_at: Time.current
    )

    MigrationAnalyticsSourceSetting
      .where.not(client_id: [ nil, "" ])
      .or(MigrationAnalyticsSourceSetting.where.not(client_secret: [ nil, "" ]))
      .or(MigrationAnalyticsSourceSetting.where.not(refresh_token: [ nil, "" ]))
      .update_all(
        google_credential_id: credential.id,
        client_id: nil,
        client_secret: nil,
        refresh_token: nil,
        credentials_json: nil,
        updated_at: Time.current
      )
  end
end

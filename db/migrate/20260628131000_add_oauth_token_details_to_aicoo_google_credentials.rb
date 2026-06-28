class AddOauthTokenDetailsToAicooGoogleCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_google_credentials, :access_token, :text
    add_column :aicoo_google_credentials, :token_expires_at, :datetime
    add_column :aicoo_google_credentials, :google_account_email, :string

    add_index :aicoo_google_credentials, :google_account_email
    add_index :aicoo_google_credentials, :token_expires_at
  end
end

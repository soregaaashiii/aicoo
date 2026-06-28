class AddLastOauthSuccessAtToAicooGoogleCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_google_credentials, :last_oauth_success_at, :datetime
  end
end

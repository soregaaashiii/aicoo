class AddGoogleCloudProjectIdToAicooGoogleCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_google_credentials, :google_cloud_project_id, :string
  end
end

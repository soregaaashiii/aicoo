class AddConnectionFieldsToBusinessDataSourceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :business_data_source_settings, :connection_status, :string, default: "unlinked", null: false
    add_column :business_data_source_settings, :external_account_id, :string
    add_column :business_data_source_settings, :property_identifier, :string
    add_column :business_data_source_settings, :endpoint_url, :string
    add_column :business_data_source_settings, :credential_reference, :string
    add_column :business_data_source_settings, :last_connected_at, :datetime
    add_column :business_data_source_settings, :notes, :text

    add_index :business_data_source_settings, :connection_status
    add_index :business_data_source_settings, :last_connected_at
  end
end

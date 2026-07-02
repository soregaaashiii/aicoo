class AddMetadataToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :metadata, :jsonb, default: {}, null: false
  end
end

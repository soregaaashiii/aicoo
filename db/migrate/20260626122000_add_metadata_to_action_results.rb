class AddMetadataToActionResults < ActiveRecord::Migration[8.1]
  def change
    add_column :action_results, :metadata, :jsonb, null: false, default: {}
  end
end

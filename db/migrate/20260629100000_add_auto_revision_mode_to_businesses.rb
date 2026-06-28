class AddAutoRevisionModeToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :auto_revision_mode, :string, null: false, default: "manual"
    add_index :businesses, :auto_revision_mode
  end
end

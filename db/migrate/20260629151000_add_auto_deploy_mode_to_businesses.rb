class AddAutoDeployModeToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :auto_deploy_mode, :string, null: false, default: "manual"
    add_index :businesses, :auto_deploy_mode
  end
end

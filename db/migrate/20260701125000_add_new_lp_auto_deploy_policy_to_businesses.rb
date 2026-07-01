class AddNewLpAutoDeployPolicyToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :new_lp_auto_deploy_enabled, :boolean, null: false, default: false
    add_column :businesses, :auto_deploy_suspended, :boolean, null: false, default: false
    add_column :businesses, :auto_deploy_suspended_at, :datetime
    add_column :businesses, :auto_deploy_suspended_reason, :string

    add_index :businesses, :new_lp_auto_deploy_enabled
    add_index :businesses, :auto_deploy_suspended
  end
end

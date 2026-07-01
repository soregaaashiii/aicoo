class AddDeployControlsToBusinessExecutionProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :business_execution_profiles, :working_branch_prefix, :string, default: "codex/auto-revision", null: false
    add_column :business_execution_profiles, :render_service_name, :string
    add_column :business_execution_profiles, :auto_merge_enabled, :boolean, default: false, null: false
    add_column :business_execution_profiles, :auto_deploy_risk_limit, :string, default: "low", null: false
    add_column :business_execution_profiles, :require_manual_approval, :boolean, default: true, null: false
    add_column :business_execution_profiles, :health_check_url, :string
    add_column :business_execution_profiles, :deploy_target, :string, default: "render", null: false

    add_index :business_execution_profiles, :auto_merge_enabled
    add_index :business_execution_profiles, :auto_deploy_risk_limit
    add_index :business_execution_profiles, :deploy_target
  end
end

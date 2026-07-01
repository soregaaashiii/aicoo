class AddCodexCloudFieldsToBusinessExecutionProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :business_execution_profiles, :codex_enabled, :boolean, null: false, default: false
    add_column :business_execution_profiles, :codex_workspace_name, :string
    add_column :business_execution_profiles, :codex_project_folder, :string
    add_column :business_execution_profiles, :codex_repository_url, :string
    add_column :business_execution_profiles, :codex_base_branch, :string, null: false, default: "main"
    add_column :business_execution_profiles, :codex_working_branch_prefix, :string, null: false, default: "aicoo/"
    add_column :business_execution_profiles, :codex_auto_submit_enabled, :boolean, null: false, default: false
    add_column :business_execution_profiles, :codex_auto_pr_enabled, :boolean, null: false, default: true
    add_column :business_execution_profiles, :codex_auto_merge_enabled, :boolean, null: false, default: false
    add_column :business_execution_profiles, :codex_auto_deploy_enabled, :boolean, null: false, default: false
    add_column :business_execution_profiles, :codex_risk_limit, :string, null: false, default: "low"
    add_column :business_execution_profiles, :codex_notes, :text

    add_index :business_execution_profiles, :codex_enabled
    add_index :business_execution_profiles, :codex_auto_submit_enabled
    add_index :business_execution_profiles, :codex_risk_limit
  end
end

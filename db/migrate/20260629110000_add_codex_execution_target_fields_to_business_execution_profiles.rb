class AddCodexExecutionTargetFieldsToBusinessExecutionProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :business_execution_profiles, :execution_type, :string, null: false, default: "aicoo_internal"
    add_column :business_execution_profiles, :target_slug, :string
    add_column :business_execution_profiles, :target_paths, :jsonb, null: false, default: []
    add_column :business_execution_profiles, :auto_deploy_enabled, :boolean, null: false, default: false
  end
end

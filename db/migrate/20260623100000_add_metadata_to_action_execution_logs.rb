class AddMetadataToActionExecutionLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :action_execution_logs, :metadata, :jsonb, default: {}, null: false
  end
end

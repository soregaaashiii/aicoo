class AddOwnerApprovalFieldsToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :approved_at, :datetime
    add_column :action_candidates, :approved_by, :string
    add_column :action_candidates, :executor_queued_at, :datetime
  end
end

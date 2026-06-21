class AddMetadataToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :metadata, :jsonb, default: {}, null: false
  end
end

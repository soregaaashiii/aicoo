class AddDataConfidenceScoreToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :data_confidence_score, :integer
  end
end

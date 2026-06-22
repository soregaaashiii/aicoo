class AddMetaEvaluationFieldsToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :final_expected_value_yen, :integer, default: 0, null: false
    add_column :action_candidates, :final_confidence_score, :integer, default: 0, null: false
  end
end

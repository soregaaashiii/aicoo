class AddOwnerValueFieldsToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :expected_revenue_value_yen, :integer, default: 0, null: false
    add_column :action_candidates, :expected_learning_value_yen, :integer, default: 0, null: false
    add_column :action_candidates, :expected_total_value_yen, :integer, default: 0, null: false
  end
end

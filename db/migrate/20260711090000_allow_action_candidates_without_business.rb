class AllowActionCandidatesWithoutBusiness < ActiveRecord::Migration[8.1]
  def change
    change_column_null :action_candidates, :business_id, true
  end
end

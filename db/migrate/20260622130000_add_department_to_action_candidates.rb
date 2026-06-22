class AddDepartmentToActionCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :action_candidates, :department, :string, default: "general", null: false
    add_index :action_candidates, :department
  end
end

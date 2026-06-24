class AddStatusToExploreObservations < ActiveRecord::Migration[8.0]
  def change
    add_column :explore_observations, :status, :string, null: false, default: "new"
    add_index :explore_observations, :status
  end
end

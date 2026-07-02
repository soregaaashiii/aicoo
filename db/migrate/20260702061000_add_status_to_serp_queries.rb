class AddStatusToSerpQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :serp_queries, :status, :string, null: false, default: "active"
    add_index :serp_queries, :status
    add_index :serp_queries, [ :business_id, :status, :priority ]
  end
end

class AddResourceControlToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :resource_status, :string, null: false, default: "active"
    add_column :businesses, :resource_status_changed_at, :datetime
    add_column :businesses, :resource_status_reason, :text
    add_column :businesses, :next_review_on, :date

    add_index :businesses, :resource_status
    add_index :businesses, :next_review_on
  end
end

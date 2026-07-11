class AddSoftDeleteToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :deleted_at, :datetime
    add_column :businesses, :deletion_reason, :string
    add_column :businesses, :deleted_by, :string
    add_column :businesses, :deletion_source, :string
    add_column :businesses, :status_before_deletion, :string

    add_index :businesses, :deleted_at
    add_index :businesses, :deletion_reason
    add_index :businesses, :deletion_source
  end
end

class AddTargetRepositoryToAutoRevisionTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :auto_revision_tasks, :target_business, null: true, foreign_key: { to_table: :businesses }
    add_column :auto_revision_tasks, :target_repository_name, :string
    add_column :auto_revision_tasks, :target_repository_type, :string
  end
end

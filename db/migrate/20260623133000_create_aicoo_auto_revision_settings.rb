class CreateAicooAutoRevisionSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_auto_revision_settings do |t|
      t.boolean :enabled, null: false, default: false
      t.integer :max_tasks_per_run, null: false, default: 5
      t.decimal :minimum_final_score, null: false, default: 1000
      t.boolean :allow_medium_risk, null: false, default: true
      t.boolean :created_by_system, null: false, default: true
      t.datetime :last_auto_queue_at

      t.timestamps
    end
  end
end

class CreateAicooSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :aicoo_settings do |t|
      t.boolean :auto_queue_data_preparation_tasks, default: false, null: false

      t.timestamps
    end
  end
end

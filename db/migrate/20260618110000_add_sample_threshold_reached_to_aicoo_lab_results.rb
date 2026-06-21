class AddSampleThresholdReachedToAicooLabResults < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_lab_results, :sample_threshold_reached, :boolean, null: false, default: false
    add_index :aicoo_lab_results, :sample_threshold_reached
  end
end

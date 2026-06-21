class AddUniqueIndexToBusinessMetricDailies < ActiveRecord::Migration[8.1]
  def change
    remove_index :business_metric_dailies, [ :business_id, :recorded_on ], if_exists: true
    add_index :business_metric_dailies, [ :business_id, :recorded_on ], unique: true
  end
end

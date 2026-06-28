class AddAveragePositionToBusinessMetricDailies < ActiveRecord::Migration[8.1]
  def change
    add_column :business_metric_dailies, :average_position, :decimal, default: 0, null: false
  end
end

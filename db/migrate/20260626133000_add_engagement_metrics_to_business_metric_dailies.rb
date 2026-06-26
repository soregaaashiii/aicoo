class AddEngagementMetricsToBusinessMetricDailies < ActiveRecord::Migration[8.1]
  def change
    change_table :business_metric_dailies, bulk: true do |t|
      t.integer :users, default: 0, null: false
      t.decimal :views_per_user, default: 0, null: false
      t.integer :average_engagement_time_seconds, default: 0, null: false
      t.decimal :engagement_rate, default: 0, null: false
      t.decimal :bounce_rate, default: 0, null: false
      t.integer :conversions, default: 0, null: false
      t.integer :event_count, default: 0, null: false
      t.integer :scroll_events, default: 0, null: false
      t.integer :internal_search_events, default: 0, null: false
    end
  end
end

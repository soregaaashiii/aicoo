class IncreaseProxyScoreWeightDecimalScale < ActiveRecord::Migration[8.1]
  WEIGHT_COLUMNS = %i[
    impressions_weight
    clicks_weight
    sessions_weight
    pageviews_weight
    phone_clicks_weight
    map_clicks_weight
    affiliate_clicks_weight
  ].freeze

  def change
    WEIGHT_COLUMNS.each do |column|
      change_column :proxy_score_weights, column, :decimal, precision: 16, scale: 8
    end
  end
end

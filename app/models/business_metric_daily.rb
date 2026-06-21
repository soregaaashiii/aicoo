class BusinessMetricDaily < ApplicationRecord
  SCORE_WEIGHTS = {
    impressions: 0.01,
    clicks: 1,
    sessions: 1,
    pageviews: 0.5,
    phone_clicks: 10,
    map_clicks: 8,
    affiliate_clicks: 20
  }.freeze

  belongs_to :business

  validates :recorded_on, presence: true
  validates :recorded_on, uniqueness: { scope: :business_id }
  SCORE_WEIGHTS.each_key do |metric|
    validates metric, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end

  def proxy_score
    weight = ProxyScoreWeight.for_business(business)
    SCORE_WEIGHTS.each_key.sum { |metric| public_send(metric).to_i * weight.weight_for(metric) }.to_f
  end
end

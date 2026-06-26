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
  ENGAGEMENT_COUNT_FIELDS = %i[
    users
    average_engagement_time_seconds
    conversions
    event_count
    scroll_events
    internal_search_events
  ].freeze
  ENGAGEMENT_RATE_FIELDS = %i[
    views_per_user
    engagement_rate
    bounce_rate
  ].freeze
  ENGAGEMENT_FIELDS = (ENGAGEMENT_COUNT_FIELDS + ENGAGEMENT_RATE_FIELDS).freeze

  belongs_to :business

  validates :recorded_on, presence: true
  validates :recorded_on, uniqueness: { scope: :business_id }
  SCORE_WEIGHTS.each_key do |metric|
    validates metric, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
  ENGAGEMENT_COUNT_FIELDS.each do |metric|
    validates metric, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
  ENGAGEMENT_RATE_FIELDS.each do |metric|
    validates metric, numericality: { greater_than_or_equal_to: 0 }
  end

  def proxy_score
    weight = ProxyScoreWeight.for_business(business)
    SCORE_WEIGHTS.each_key.sum { |metric| public_send(metric).to_i * weight.weight_for(metric) }.to_f
  end

  def views_per_session
    return 0.to_d if sessions.to_i.zero?

    pageviews.to_d / sessions.to_d
  end

  def conversion_rate
    return 0.to_d if sessions.to_i.zero?

    conversions.to_d / sessions.to_d
  end

  def scroll_rate
    return 0.to_d if sessions.to_i.zero?

    scroll_events.to_d / sessions.to_d
  end

  def engagement_score
    time_score = [ average_engagement_time_seconds.to_d / 180 * 35, 35 ].min
    navigation_score = [ views_per_session / 3 * 25, 25 ].min
    engagement_score = [ engagement_rate.to_d * 25, 25 ].min
    conversion_score = [ conversion_rate * 15, 15 ].min
    bounce_penalty = [ bounce_rate.to_d * 20, 20 ].min

    [ time_score + navigation_score + engagement_score + conversion_score - bounce_penalty, 0 ].max.round(2)
  end
end

class ProxyScoreWeightAdjustmentLog < ApplicationRecord
  belongs_to :proxy_score_weight
  belongs_to :business, optional: true

  validates :start_date, :end_date, :reason, :adjusted_at, presence: true
  validates :confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :sample_days_count, :revenue_events_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :adjustment_rate, numericality: { greater_than_or_equal_to: 0 }
end

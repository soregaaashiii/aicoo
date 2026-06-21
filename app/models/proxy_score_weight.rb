class ProxyScoreWeight < ApplicationRecord
  DEFAULT_WEIGHTS = {
    impressions_weight: 0.01,
    clicks_weight: 1.0,
    sessions_weight: 1.0,
    pageviews_weight: 0.5,
    phone_clicks_weight: 10.0,
    map_clicks_weight: 8.0,
    affiliate_clicks_weight: 20.0
  }.freeze

  METRIC_TO_WEIGHT = {
    impressions: :impressions_weight,
    clicks: :clicks_weight,
    sessions: :sessions_weight,
    pageviews: :pageviews_weight,
    phone_clicks: :phone_clicks_weight,
    map_clicks: :map_clicks_weight,
    affiliate_clicks: :affiliate_clicks_weight
  }.freeze

  SAFETY_RANGES = {
    impressions_weight: 0.001..0.1,
    clicks_weight: 0.1..10.0,
    sessions_weight: 0.1..10.0,
    pageviews_weight: 0.05..5.0,
    phone_clicks_weight: 5.0..100.0,
    map_clicks_weight: 5.0..100.0,
    affiliate_clicks_weight: 10.0..200.0
  }.freeze

  belongs_to :business, optional: true
  has_many :proxy_score_weight_adjustment_logs, dependent: :destroy

  validates :source_type, presence: true
  validates :confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  DEFAULT_WEIGHTS.each_key do |column|
    validates column, numericality: true
  end

  before_validation :set_default_weights
  before_save :clamp_weights

  scope :global, -> { where(business_id: nil) }

  def self.current_global
    global.order(updated_at: :desc).first
  end

  def self.for_business(business)
    where(business:).order(updated_at: :desc).first || current_global || new(default_attributes)
  end

  def self.default_attributes
    DEFAULT_WEIGHTS.merge(source_type: "code_default", confidence_score: 0)
  end

  def self.build_for_business!(business)
    find_or_initialize_by(business:).tap do |weight|
      source = current_global || new(default_attributes)
      weight.assign_missing_weights_from(source)
      weight.source_type = "business_adjusted"
      weight.save! if weight.new_record?
    end
  end

  def self.build_global!
    global.order(updated_at: :desc).first_or_initialize.tap do |weight|
      weight.source_type = "global_adjusted"
      weight.save! if weight.new_record?
    end
  end

  def assign_missing_weights_from(source)
    self.class::DEFAULT_WEIGHTS.each_key do |column|
      public_send("#{column}=", source.public_send(column)) if public_send(column).blank?
    end
  end

  def weights_hash
    self.class::DEFAULT_WEIGHTS.keys.index_with { |column| public_send(column).to_d }
  end

  def weight_for(metric)
    column = self.class::METRIC_TO_WEIGHT.fetch(metric.to_sym)
    public_send(column).to_d
  end

  def clamp_weights
    self.class::SAFETY_RANGES.each do |column, range|
      value = public_send(column).to_d
      public_send("#{column}=", [ [ value, range.min.to_d ].max, range.max.to_d ].min)
    end
  end

  private

  def set_default_weights
    self.class::DEFAULT_WEIGHTS.each do |column, value|
      public_send("#{column}=", value) if public_send(column).blank?
    end
    self.source_type = "default" if source_type.blank?
    self.confidence_score = 0 if confidence_score.blank?
  end
end

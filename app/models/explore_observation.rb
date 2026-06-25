class ExploreObservation < ApplicationRecord
  OBSERVATION_TYPES = %w[
    trend
    competitor
    discussion
    engagement
    opportunity
    anomaly
  ].freeze

  STATUSES = %w[new reviewed converted rejected on_hold].freeze

  belongs_to :explore_data_source
  belongs_to :opportunity_discovery_item, optional: true

  before_validation :set_defaults

  validates :title, presence: true
  validates :observation_type, inclusion: { in: OBSERVATION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :recent, -> { order(observed_at: :desc, created_at: :desc) }
  scope :top_ranked, -> { order(Arel.sql("score DESC NULLS LAST, observed_at DESC NULLS LAST, created_at DESC")) }
  scope :unconverted, -> { where(opportunity_discovery_item_id: nil) }
  scope :new_status, -> { where(status: "new") }
  scope :high_score, -> { where("score >= ?", 80) }

  def convert_to_opportunity!
    return opportunity_discovery_item if opportunity_discovery_item

    Aicoo::ExploreOpportunityGenerator.new(observations: ExploreObservation.where(id:)).generate_from_observation!(self, force: true)
  end

  def mark_reviewed!
    update!(status: "reviewed")
  end

  def reject!
    update!(status: "rejected")
  end

  def hold!
    update!(status: "on_hold")
  end

  private

  def set_defaults
    self.observation_type = "opportunity" if observation_type.blank?
    self.status = "new" if status.blank?
    self.score = 50 if score.nil?
    self.observed_at ||= Time.current
  end
end

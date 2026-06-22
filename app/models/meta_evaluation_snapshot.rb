class MetaEvaluationSnapshot < ApplicationRecord
  EVALUATOR_TYPES = %w[gsc ga4 judge revenue learning].freeze

  belongs_to :aicoo_daily_run, optional: true
  belongs_to :business, optional: true

  validates :recorded_on, presence: true
  validates :evaluator_type, inclusion: { in: EVALUATOR_TYPES }
  validates :evaluator_type, uniqueness: { scope: [ :recorded_on, :business_id ] }, if: :business_id?
  validates :evaluator_type,
            uniqueness: { scope: :recorded_on, conditions: -> { where(business_id: nil) } },
            unless: :business_id?
  validates :average_expected_value_yen, :candidate_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :average_confidence_score, :weighted_contribution_score, numericality: { greater_than_or_equal_to: 0 }

  scope :global, -> { where(business_id: nil) }
  scope :recent, -> { order(recorded_on: :desc, evaluator_type: :asc) }
  scope :for_date, ->(date) { where(recorded_on: date) }

  def self.latest_global
    global.for_date(global.maximum(:recorded_on) || Date.current)
  end
end

class AicooLabGenerationRun < ApplicationRecord
  GENERATION_TYPES = %w[candidate_generation lp_generation scoring_assist other].freeze
  STATUSES = %w[draft running succeeded failed].freeze

  has_many :aicoo_lab_ai_drafts, foreign_key: :generation_run_id, dependent: :destroy, inverse_of: :generation_run

  validates :generation_type, inclusion: { in: GENERATION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :generated_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
end

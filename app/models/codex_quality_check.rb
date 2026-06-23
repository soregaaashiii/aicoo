class CodexQualityCheck < ApplicationRecord
  RESULTS = %w[passed passed_with_warnings review_required failed].freeze
  TEST_STATUSES = %w[passed failed unknown].freeze

  belongs_to :auto_revision_task

  validates :quality_score, :risk_score, :changed_files_count, :warning_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :result, inclusion: { in: RESULTS }
  validates :test_status, inclusion: { in: TEST_STATUSES }

  scope :recent_warnings, -> {
    where(result: %w[passed_with_warnings review_required failed]).order(updated_at: :desc)
  }

  def review_required?
    result.in?(%w[review_required failed])
  end
end

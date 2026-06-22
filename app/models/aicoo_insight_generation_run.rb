class AicooInsightGenerationRun < ApplicationRecord
  STATUSES = %w[running success failed].freeze
  SOURCES = %w[manual daily_run].freeze

  validates :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :generated_count, :skipped_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }
  scope :today, -> { where(started_at: Time.current.all_day) }
  scope :failed, -> { where(status: "failed") }
end

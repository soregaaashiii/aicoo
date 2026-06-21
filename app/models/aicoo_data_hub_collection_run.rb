class AicooDataHubCollectionRun < ApplicationRecord
  STATUSES = %w[running success failed].freeze

  validates :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :snapshot_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :set_defaults

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }

  private

  def set_defaults
    self.started_at ||= Time.current
    self.status ||= "running"
    self.snapshot_count ||= 0
  end
end

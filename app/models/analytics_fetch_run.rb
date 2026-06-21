class AnalyticsFetchRun < ApplicationRecord
  STATUSES = %w[running success failed].freeze

  belongs_to :analytics_source_setting

  before_validation :set_defaults

  validates :source_type, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :snapshot_count, :updated_neglect_loss_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }

  private

  def set_defaults
    self.source_type = analytics_source_setting&.source_type if source_type.blank?
    self.status = "running" if status.blank?
    self.started_at = Time.current if started_at.blank?
    self.snapshot_count = 0 if snapshot_count.blank?
    self.updated_neglect_loss_count = 0 if updated_neglect_loss_count.blank?
  end
end

class AutoRevisionQueueRun < ApplicationRecord
  belongs_to :aicoo_daily_run, optional: true

  validates :generated_tasks_count, :skipped_candidates_count, :high_risk_candidates_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :executed_at, presence: true

  scope :recent, -> { order(executed_at: :desc, created_at: :desc) }

  before_validation :set_defaults

  private

  def set_defaults
    self.executed_at ||= Time.current
    self.metadata ||= {}
  end
end

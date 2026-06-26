class SystemModeSnapshot < ApplicationRecord
  STALE_AFTER = 12.hours

  validates :captured_at, presence: true
  validates :health_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :warning_count, :critical_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(captured_at: :desc, created_at: :desc) }

  def self.latest
    recent.first
  end

  def stale?
    captured_at < STALE_AFTER.ago
  end

  def age_seconds
    return 0 unless captured_at

    (Time.current - captured_at).to_i
  end
end

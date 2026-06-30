class ActivityEvaluation < ApplicationRecord
  STATUSES = %w[pending evaluated skipped].freeze

  belongs_to :business_activity_log
  belongs_to :business

  enum :status, {
    pending: "pending",
    evaluated: "evaluated",
    skipped: "skipped"
  }, validate: true

  validates :evaluation_window_days, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :evaluation_window_days, uniqueness: { scope: :business_activity_log_id }
end

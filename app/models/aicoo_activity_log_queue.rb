class AicooActivityLogQueue < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  enum :status, {
    pending: "pending",
    sent: "sent",
    failed: "failed"
  }, validate: true

  validates :payload, presence: true
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :retryable, -> {
    where(status: "pending")
      .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.current)
      .order(:created_at)
  }

  def schedule_retry!(error_message)
    increment!(:attempts)
    update!(
      status: "pending",
      last_attempted_at: Time.current,
      next_retry_at: Time.current + retry_delay,
      error_message:
    )
  end

  def mark_sent!
    update!(status: "sent", last_attempted_at: Time.current, error_message: nil)
  end

  private

  def retry_delay
    [ 5.minutes, 30.minutes, 2.hours, 1.day ].fetch([ attempts, 3 ].min)
  end
end

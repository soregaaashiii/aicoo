class CodexSubmission < ApplicationRecord
  STATUSES = %w[draft ready submitted failed completed cancelled].freeze

  belongs_to :auto_revision_task
  belongs_to :business
  belongs_to :business_execution_profile

  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true
  validates :base_branch, presence: true
  validates :working_branch, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :ready, -> { where(status: "ready") }
  scope :draft, -> { where(status: "draft") }
  scope :failed, -> { where(status: "failed") }

  def mark_ready!
    update!(status: "ready")
  end

  def mark_submitted!(payload: {})
    update!(
      status: "submitted",
      submitted_at: Time.current,
      response_payload: response_payload.to_h.merge(payload.to_h)
    )
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  def mark_completed!(payload: {})
    update!(
      status: "completed",
      completed_at: Time.current,
      response_payload: response_payload.to_h.merge(payload.to_h)
    )
  end
end

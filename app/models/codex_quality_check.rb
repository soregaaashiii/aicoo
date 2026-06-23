class CodexQualityCheck < ApplicationRecord
  RESULTS = %w[passed passed_with_warnings review_required failed].freeze
  TEST_STATUSES = %w[passed failed unknown].freeze
  APPROVAL_STATUSES = %w[pending approved rejected].freeze

  belongs_to :auto_revision_task

  validates :quality_score, :risk_score, :changed_files_count, :warning_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :result, inclusion: { in: RESULTS }
  validates :test_status, inclusion: { in: TEST_STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  scope :recent_warnings, -> {
    where(result: %w[passed_with_warnings review_required failed]).order(updated_at: :desc)
  }
  scope :pending_review, -> { where(approval_status: "pending") }

  def review_required?
    result.in?(%w[review_required failed])
  end

  def approve!(approved_by: nil, approval_note: nil)
    update!(
      approval_status: "approved",
      approved_at: Time.current,
      approved_by:,
      approval_note:
    )
  end

  def reject!(approved_by: nil, approval_note: nil)
    update!(
      approval_status: "rejected",
      approved_at: nil,
      approved_by:,
      approval_note:
    )
  end

  def learning_loop_verified?
    approval_status == "approved"
  end

  def quality_gate_label
    case approval_status
    when "approved"
      "Approved"
    when "rejected"
      "Rejected"
    else
      "Pending Review"
    end
  end
end

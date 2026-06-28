class AutoRevisionRunLog < ApplicationRecord
  STATUSES = %w[pending precheck_failed queued_for_approval sent_to_codex deploy_pending succeeded failed rolled_back].freeze

  belongs_to :business
  belongs_to :auto_revision_task, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :auto_revision_mode, inclusion: { in: Business::AUTO_REVISION_MODES }
  validates :changed_files_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Time.zone.today.all_day) }

  before_validation :set_defaults

  def mark_rolled_back!(message: nil)
    update!(
      status: "rolled_back",
      rollback_status: "requested",
      message: message.presence || "Rollback requested",
      finished_at: Time.current
    )
  end

  private

  def set_defaults
    self.auto_revision_mode ||= business&.auto_revision_mode || "manual"
    self.status ||= "pending"
    self.metadata ||= {}
  end
end

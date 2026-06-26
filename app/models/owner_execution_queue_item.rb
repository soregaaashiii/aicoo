class OwnerExecutionQueueItem < ApplicationRecord
  ITEM_TYPES = %w[
    action_candidate
    opportunity
    codex_prompt_draft
    result_registration
    calibration
  ].freeze
  STATUSES = %w[pending processing completed skipped expired].freeze
  RISK_LEVELS = %w[low medium high].freeze

  belongs_to :business, optional: true

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :title, :due_on, presence: true
  validates :item_id, uniqueness: { scope: %i[item_type due_on] }

  scope :today, -> { where(due_on: Date.current) }
  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :skipped, -> { where(status: "skipped") }
  scope :ordered, -> { order(priority_score: :desc, expected_value_yen: :desc, created_at: :asc) }

  def complete!
    update!(status: "completed")
  end

  def skip!
    update!(status: "skipped")
  end

  def restore!
    update!(status: "pending")
  end

  def target_path
    routes = Rails.application.routes.url_helpers
    case item_type
    when "action_candidate"
      routes.action_candidate_path(item_id)
    when "opportunity"
      routes.owner_opportunity_path(item_id)
    when "codex_prompt_draft"
      routes.owner_codex_prompt_draft_path(item_id)
    when "result_registration"
      routes.action_execution_path(item_id)
    when "calibration"
      routes.admin_aicoo_calibration_path(filter: "pending")
    else
      routes.owner_tasks_path
    end
  end
end

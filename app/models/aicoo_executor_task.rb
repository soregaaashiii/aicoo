class AicooExecutorTask < ApplicationRecord
  SOURCE_TYPES = %w[action_candidate lab_candidate lab_experiment].freeze
  EXECUTION_TYPES = %w[
    seo_content
    seo_update
    shop_import
    lp_creation
    market_research
    customer_interview
    data_collection
    data_preparation
    custom
  ].freeze
  STATUSES = %w[draft approval_pending approved done rejected].freeze

  validates :title, :source_type, :source_id, :execution_type, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :execution_type, inclusion: { in: EXECUTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :estimated_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :waiting_execution, -> { where(status: "approved") }
  scope :approval_pending, -> { where(status: "approval_pending") }
  scope :done, -> { where(status: "done") }
  scope :data_preparation, -> { where(execution_type: "data_preparation") }
  scope :unfinished, -> { where.not(status: %w[done rejected]) }

  def self.unfinished_for_action_candidate(action_candidate)
    unfinished.find_by(source_type: "action_candidate", source_id: action_candidate.id)
  end

  before_validation :set_defaults

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end

  def reject!
    update!(status: "rejected")
  end

  def complete!
    update!(status: "done", done_at: Time.current)
  end

  def source_record
    case source_type
    when "action_candidate"
      ActionCandidate.find_by(id: source_id)
    when "lab_candidate"
      AicooLabExperimentCandidate.find_by(id: source_id)
    when "lab_experiment"
      AicooLabExperiment.find_by(id: source_id)
    end
  end

  private

  def set_defaults
    self.execution_type = "custom" if execution_type.blank?
    self.status = "draft" if status.blank?
  end
end

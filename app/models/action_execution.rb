class ActionExecution < ApplicationRecord
  STATUSES = %w[pending ready running completed failed cancelled].freeze
  EXECUTION_TYPES = %w[manual codex external_ai other].freeze

  belongs_to :action_candidate
  has_one :business, through: :action_candidate
  has_one :action_result, dependent: :nullify

  before_validation :set_defaults
  before_validation :copy_prediction_snapshot, on: :create

  validates :status, inclusion: { in: STATUSES }
  validates :execution_type, inclusion: { in: EXECUTION_TYPES }, allow_blank: true
  validates :actual_hours, :actual_cost_yen, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ready, -> { where(status: "ready") }
  scope :running, -> { where(status: "running") }
  scope :completed_today, -> { where(status: "completed", completed_at: Date.current.all_day) }
  scope :failed_today, -> { where(status: "failed", completed_at: Date.current.all_day) }
  scope :completed_without_result, -> { where(status: "completed").left_outer_joins(:action_result).where(action_results: { id: nil }) }
  scope :recent, -> { order(updated_at: :desc, created_at: :desc) }

  def start!
    update!(status: "running", started_at: Time.current)
  end

  def complete!(actual_hours: nil, actual_cost_yen: nil, result_summary: nil)
    update!(
      status: "completed",
      completed_at: Time.current,
      actual_hours: actual_hours.presence || self.actual_hours,
      actual_cost_yen: actual_cost_yen.presence || self.actual_cost_yen,
      result_summary: result_summary.presence || self.result_summary
    )
  end

  def fail!(result_summary: nil)
    update!(
      status: "failed",
      completed_at: Time.current,
      result_summary: result_summary.presence || self.result_summary
    )
  end

  def cancel!
    update!(status: "cancelled", completed_at: Time.current)
  end

  private

  def set_defaults
    self.status = "ready" if status.blank?
    self.execution_type = "manual" if execution_type.blank?
    self.execution_prompt = Aicoo::ExecutionPromptBuilder.new(action_candidate).call if execution_prompt.blank? && action_candidate
  end

  def copy_prediction_snapshot
    return unless action_candidate

    self.predicted_profit_yen_snapshot = action_candidate.expected_profit_yen.to_i if predicted_profit_yen_snapshot.nil?
    if predicted_success_probability_snapshot.nil?
      self.predicted_success_probability_snapshot = action_candidate.calibrated_success_probability.to_d
    end
    self.predicted_hours_snapshot = action_candidate.expected_hours if predicted_hours_snapshot.nil?
    self.predicted_cost_yen_snapshot = action_candidate.cost_yen.to_i if predicted_cost_yen_snapshot.nil?
    self.action_score_snapshot = snapshot_action_score if action_score_snapshot.nil?
  end

  def snapshot_action_score
    return action_candidate.final_score.to_d if action_candidate.final_score.present?

    action_candidate.calculate_final_score.to_d
  end
end

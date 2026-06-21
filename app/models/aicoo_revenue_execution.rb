class AicooRevenueExecution < ApplicationRecord
  SOURCE_TYPES = %w[candidate experiment action_candidate].freeze
  STATUSES = %w[planned done skipped].freeze
  PREDICTION_SOURCES = %w[human lab revenue].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :prediction_source, inclusion: { in: PREDICTION_SOURCES }
  validates :source_id, :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :neglect_loss_90d_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :actual_90d_profit_yen, numericality: { only_integer: true }, allow_nil: true
  validate :planned_source_is_unique, if: -> { status == "planned" }

  scope :recent, -> { order(planned_at: :desc, created_at: :desc) }
  scope :planned, -> { where(status: "planned") }
  scope :done, -> { where(status: "done") }
  scope :scored, -> { where.not(actual_90d_profit_yen: nil) }

  before_validation :set_defaults
  before_save :calculate_result_metrics

  def mark_done!
    update!(status: "done", done_at: Time.current)
  end

  def mark_skipped!(note: nil)
    assign_attributes(status: "skipped", skipped_at: Time.current)
    self.note = note if note.present?
    save!
  end

  def predicted_value
    revenue_total_value_yen.to_i
  end

  def source_record
    case source_type
    when "candidate"
      AicooLabExperimentCandidate.find_by(id: source_id)
    when "experiment"
      AicooLabExperiment.find_by(id: source_id)
    when "action_candidate"
      ActionCandidate.find_by(id: source_id)
    end
  end

  def source_status
    source_record&.status
  end

  def action_candidate_source?
    source_type == "action_candidate"
  end

  def source_action_candidate
    return unless action_candidate_source?

    source_record
  end

  private

  def set_defaults
    self.status ||= "planned"
    self.prediction_source ||= "revenue"
    self.planned_at ||= Time.current if status == "planned"
    self.neglect_loss_90d_yen ||= 0
  end

  def calculate_result_metrics
    return clear_result_metrics if actual_90d_profit_yen.nil?

    self.measured_at ||= Time.current
    return clear_result_metrics if predicted_value.zero?

    self.error_rate = (predicted_value - actual_90d_profit_yen).abs.to_d / predicted_value
    self.calibration_score = [ 100.to_d - (error_rate * 100), 0.to_d ].max
  end

  def clear_result_metrics
    self.error_rate = nil
    self.calibration_score = nil
  end

  def planned_source_is_unique
    duplicate = self.class.where(source_type:, source_id:, status: "planned")
    duplicate = duplicate.where.not(id:) if persisted?
    errors.add(:source_id, "is already planned") if duplicate.exists?
  end
end

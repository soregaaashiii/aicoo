class ActionResult < ApplicationRecord
  include AicooActivityTrackable

  EVALUATION_STATUSES = %w[pending evaluated skipped].freeze
  DELTA_METRICS = %i[
    impressions
    clicks
    sessions
    pageviews
    phone_clicks
    map_clicks
    affiliate_clicks
  ].freeze

  belongs_to :action_candidate
  belongs_to :business
  belongs_to :action_execution, optional: true
  has_many :action_execution_logs, dependent: :nullify
  has_many :revenue_events, dependent: :nullify

  before_validation :copy_prediction_snapshot, on: :create
  before_validation :set_default_status
  before_save :calculate_prediction_error
  after_commit :auto_link_action_execution_log, on: %i[create update]

  validates :executed_on, :evaluated_on, presence: true
  validates :evaluation_status, inclusion: { in: EVALUATION_STATUSES }
  validates :actual_revenue_yen, :actual_profit_yen, numericality: { only_integer: true }
  validates :predicted_success_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :action_execution_id, uniqueness: true, allow_nil: true

  scope :pending, -> { where(evaluation_status: "pending") }
  scope :evaluated, -> { where(evaluation_status: "evaluated") }
  scope :skipped, -> { where(evaluation_status: "skipped") }

  private

  def copy_prediction_snapshot
    self.business ||= action_candidate&.business
    self.action_candidate ||= action_execution&.action_candidate
    self.business ||= action_execution&.business
    self.predicted_value_yen = action_candidate&.immediate_value_yen.to_i if predicted_value_yen.nil?
    if predicted_success_probability.nil? && action_execution
      self.predicted_success_probability = action_execution.predicted_success_probability_snapshot.to_d
    elsif predicted_success_probability.nil?
      self.predicted_success_probability = action_candidate&.calibrated_success_probability.to_d
    end
    return unless predicted_expected_profit_yen.nil?

    self.predicted_expected_profit_yen = if action_execution
      action_execution.predicted_profit_yen_snapshot.to_i
    else
      action_candidate&.expected_profit_yen.to_i
    end
  end

  def set_default_status
    self.evaluation_status = "pending" if evaluation_status.blank?
  end

  def calculate_prediction_error
    predicted = predicted_expected_profit_yen.to_i
    actual = actual_profit_yen.to_i
    self.prediction_error_yen = (predicted - actual).abs
    self.prediction_error_rate = predicted.positive? ? prediction_error_yen.to_d / predicted : nil
  end

  def auto_link_action_execution_log
    AicooLearningLoopAutoLinkService.new(self).call
  end
end

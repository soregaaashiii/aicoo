class AicooLabPrediction < ApplicationRecord
  TYPES = %w[profit pv signup_rate ctr conversion_rate revenue].freeze
  UNITS = %w[yen count percent].freeze
  TARGET_DAYS = [ 7, 30, 90 ].freeze
  PREDICTION_SOURCES = %w[human lab revenue].freeze

  belongs_to :aicoo_lab_experiment

  before_validation :set_defaults

  validates :prediction_type, inclusion: { in: TYPES }
  validates :target_days, inclusion: { in: TARGET_DAYS }
  validates :predicted_value, numericality: true
  validates :predicted_value_unit, inclusion: { in: UNITS }
  validates :prediction_source, inclusion: { in: PREDICTION_SOURCES }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  private

  def set_defaults
    self.prediction_type = "profit" if prediction_type.blank?
    self.prediction_source = "lab" if prediction_source.blank?
    self.target_days = 90 if target_days.blank?
    self.predicted_value_unit = "yen" if predicted_value_unit.blank?
    self.predicted_at = Time.current if predicted_at.blank?
  end
end

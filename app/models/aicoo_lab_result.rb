class AicooLabResult < ApplicationRecord
  TYPES = AicooLabPrediction::TYPES
  UNITS = AicooLabPrediction::UNITS
  TARGET_DAYS = AicooLabPrediction::TARGET_DAYS

  belongs_to :aicoo_lab_experiment

  before_validation :set_defaults
  before_save :set_sample_threshold_reached
  before_save :set_formal_score

  validates :result_type, inclusion: { in: TYPES }
  validates :target_days, inclusion: { in: TARGET_DAYS }
  validates :actual_value, numericality: true
  validates :actual_value_unit, inclusion: { in: UNITS }
  validates :sample_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  private

  def set_defaults
    self.result_type = "profit" if result_type.blank?
    self.target_days = 90 if target_days.blank?
    self.actual_value_unit = "yen" if actual_value_unit.blank?
    self.measured_at = Time.current if measured_at.blank?
  end

  def set_sample_threshold_reached
    self.sample_threshold_reached = sample_size.to_i >= aicoo_lab_experiment.sample_pv_threshold.to_i
  end

  def set_formal_score
    self.is_formal_score = sample_threshold_reached || target_days == 90
  end
end

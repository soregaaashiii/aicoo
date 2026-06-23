class ActionPredictionCalibration < ApplicationRecord
  MIN_SAMPLE_SIZE = 10
  MIN_FACTOR = 0.1.to_d
  MAX_FACTOR = 3.0.to_d

  validates :action_type, presence: true, uniqueness: true
  validates :sample_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :profit_calibration_factor,
            :probability_calibration_factor,
            numericality: { greater_than_or_equal_to: MIN_FACTOR, less_than_or_equal_to: MAX_FACTOR }

  def self.for_action_type(action_type)
    find_by(action_type:) || new(
      action_type:,
      sample_count: 0,
      profit_calibration_factor: 1.0,
      probability_calibration_factor: 1.0
    )
  end

  def active?
    sample_count.to_i >= MIN_SAMPLE_SIZE
  end

  def profit_factor
    active? ? profit_calibration_factor.to_d : 1.to_d
  end

  def probability_factor
    active? ? probability_calibration_factor.to_d : 1.to_d
  end
end

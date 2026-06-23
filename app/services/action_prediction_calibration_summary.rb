class ActionPredictionCalibrationSummary
  Summary = Data.define(
    :total_sample_count,
    :average_profit_error_rate,
    :calibrated_action_type_count,
    :most_overestimated,
    :most_underestimated,
    :last_calculated_at
  )

  def call
    calibrations = ActionPredictionCalibration.all.to_a
    Summary.new(
      total_sample_count: calibrations.sum(&:sample_count),
      average_profit_error_rate: weighted_average_error_rate(calibrations),
      calibrated_action_type_count: calibrated_action_type_count(calibrations),
      most_overestimated: calibrations.min_by { |calibration| calibration.profit_calibration_factor.to_d },
      most_underestimated: calibrations.max_by { |calibration| calibration.profit_calibration_factor.to_d },
      last_calculated_at: calibrations.filter_map(&:last_calculated_at).max
    )
  end

  private

  def weighted_average_error_rate(calibrations)
    weighted_values = calibrations.filter_map do |calibration|
      next if calibration.avg_profit_error_rate.nil? || calibration.sample_count.to_i.zero?

      calibration.avg_profit_error_rate.to_d * calibration.sample_count
    end
    total_samples = calibrations.sum { |calibration| calibration.avg_profit_error_rate.nil? ? 0 : calibration.sample_count.to_i }
    return nil if weighted_values.empty? || total_samples.zero?

    weighted_values.sum / total_samples
  end

  def calibrated_action_type_count(calibrations)
    calibrations.count do |calibration|
      calibration.sample_count.to_i >= ActionPredictionCalibration::MIN_SAMPLE_SIZE &&
        (calibration.profit_calibration_factor.to_d != 1.to_d ||
         calibration.probability_calibration_factor.to_d != 1.to_d)
    end
  end
end

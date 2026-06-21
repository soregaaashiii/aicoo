class AicooLabErrorMetric < ApplicationRecord
  belongs_to :aicoo_lab_experiment
  belongs_to :aicoo_lab_prediction
  belongs_to :aicoo_lab_result

  before_validation :set_defaults
  before_save :calculate_metrics

  validates :aicoo_lab_prediction_id, uniqueness: { scope: :aicoo_lab_result_id }

  def self.recalculate_for_experiment!(experiment)
    transaction do
      experiment.aicoo_lab_error_metrics.destroy_all

      experiment.aicoo_lab_predictions.find_each do |prediction|
        matching_results = experiment.aicoo_lab_results.where(
          result_type: prediction.prediction_type,
          target_days: prediction.target_days,
          actual_value_unit: prediction.predicted_value_unit
        )

        matching_results.find_each do |result|
          create!(aicoo_lab_experiment: experiment, aicoo_lab_prediction: prediction, aicoo_lab_result: result)
        end
      end
    end
  end

  private

  def set_defaults
    self.aicoo_lab_experiment ||= aicoo_lab_prediction&.aicoo_lab_experiment || aicoo_lab_result&.aicoo_lab_experiment
    self.calculated_at = Time.current if calculated_at.blank?
  end

  def calculate_metrics
    predicted = aicoo_lab_prediction.predicted_value.to_d
    actual = aicoo_lab_result.actual_value.to_d
    self.absolute_error = (predicted - actual).abs
    self.error_rate = predicted.zero? ? nil : absolute_error / predicted
    self.calibration_score = error_rate.nil? ? nil : [ 100 - (error_rate * 100), 0 ].max
  end
end

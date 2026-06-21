require "test_helper"

class AicooLabErrorMetricTest < ActiveSupport::TestCase
  test "recalculates error metrics from matching predictions and results" do
    experiment = AicooLabExperiment.create!(title: "Metric test", experiment_type: "lp", acquisition_channel: "seo")
    prediction = experiment.aicoo_lab_predictions.create!(
      prediction_type: "profit",
      target_days: 90,
      predicted_value: 10_000,
      predicted_value_unit: "yen"
    )
    result = experiment.aicoo_lab_results.create!(
      result_type: "profit",
      target_days: 90,
      actual_value: 8_000,
      actual_value_unit: "yen",
      sample_size: 100
    )

    assert result.is_formal_score

    AicooLabErrorMetric.recalculate_for_experiment!(experiment)
    metric = experiment.reload.aicoo_lab_error_metrics.first

    assert_equal prediction, metric.aicoo_lab_prediction
    assert_equal result, metric.aicoo_lab_result
    assert_equal 2_000.to_d, metric.absolute_error
    assert_equal 0.2.to_d, metric.error_rate
    assert_equal 80.to_d, metric.calibration_score
  end
end

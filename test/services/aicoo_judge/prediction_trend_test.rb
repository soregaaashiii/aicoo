require "test_helper"

module AicooJudge
  class PredictionTrendTest < ActiveSupport::TestCase
    test "returns average calibration score by date and source" do
      create_revenue_execution(source: "revenue", predicted: 10_000, actual: 9_000, measured_at: Time.zone.local(2026, 6, 18, 10, 0, 0))
      create_revenue_execution(source: "revenue", predicted: 10_000, actual: 8_000, measured_at: Time.zone.local(2026, 6, 18, 12, 0, 0))
      create_lab_metric(source: "lab", predicted: 10_000, actual: 7_000, calculated_at: Time.zone.local(2026, 6, 19, 10, 0, 0))

      points = PredictionTrend.new.call
      revenue_point = points.find { |point| point.date == Date.new(2026, 6, 18) && point.prediction_source == "revenue" }
      lab_point = points.find { |point| point.date == Date.new(2026, 6, 19) && point.prediction_source == "lab" }

      assert_equal 85.to_d, revenue_point.average_calibration_score
      assert_equal 70.to_d, lab_point.average_calibration_score
    end

    private

    def create_lab_metric(source:, predicted:, actual:, calculated_at:)
      experiment = AicooLabExperiment.create!(title: "Judge trend #{source}", experiment_type: "lp", acquisition_channel: "seo")
      prediction = experiment.aicoo_lab_predictions.create!(
        prediction_type: "profit",
        prediction_source: source,
        target_days: 90,
        predicted_value: predicted,
        predicted_value_unit: "yen"
      )
      result = experiment.aicoo_lab_results.create!(
        result_type: "profit",
        target_days: 90,
        actual_value: actual,
        actual_value_unit: "yen",
        sample_size: 100
      )
      metric = AicooLabErrorMetric.create!(aicoo_lab_prediction: prediction, aicoo_lab_result: result)
      metric.update_columns(calculated_at:)
    end

    def create_revenue_execution(source:, predicted:, actual:, measured_at:)
      execution = AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: AicooRevenueExecution.maximum(:source_id).to_i + 1,
        title: "Judge trend revenue #{source}",
        expected_90d_profit_yen: predicted,
        success_probability: 1,
        revenue_total_value_yen: predicted,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "done",
        prediction_source: source,
        actual_90d_profit_yen: actual
      )
      execution.update_columns(measured_at:)
    end
  end
end

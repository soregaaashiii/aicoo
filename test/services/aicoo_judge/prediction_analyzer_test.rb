require "test_helper"

module AicooJudge
  class PredictionAnalyzerTest < ActiveSupport::TestCase
    test "aggregates scored predictions by source" do
      create_lab_metric(source: "lab", predicted: 10_000, actual: 8_000)
      create_lab_metric(source: "human", predicted: 10_000, actual: 5_000)
      create_revenue_execution(source: "revenue", predicted: 10_000, actual: 9_000)

      result = PredictionAnalyzer.new.call
      summaries = result.source_summaries.index_by(&:prediction_source)

      assert_equal 3, result.prediction_count
      assert_equal 0.2.to_d, summaries.fetch("lab").average_error_rate
      assert_equal 80.to_d, summaries.fetch("lab").average_calibration_score
      assert_equal 0.5.to_d, summaries.fetch("human").average_error_rate
      assert_equal 50.to_d, summaries.fetch("human").average_calibration_score
      assert_equal 0.1.to_d, summaries.fetch("revenue").average_error_rate
      assert_equal 90.to_d, summaries.fetch("revenue").average_calibration_score
    end

    test "ranks sources by calibration score and exposes winner" do
      create_lab_metric(source: "lab", predicted: 10_000, actual: 7_000)
      create_revenue_execution(source: "revenue", predicted: 10_000, actual: 9_000)
      create_lab_metric(source: "human", predicted: 10_000, actual: 6_000)

      result = PredictionAnalyzer.new.call

      assert_equal "revenue", result.winner.prediction_source
      assert_equal %w[revenue lab human], result.ranking.map(&:prediction_source)
    end

    private

    def create_lab_metric(source:, predicted:, actual:)
      experiment = AicooLabExperiment.create!(title: "Judge lab #{source}", experiment_type: "lp", acquisition_channel: "seo")
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

      AicooLabErrorMetric.create!(aicoo_lab_prediction: prediction, aicoo_lab_result: result)
    end

    def create_revenue_execution(source:, predicted:, actual:)
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: AicooRevenueExecution.maximum(:source_id).to_i + 1,
        title: "Judge revenue #{source}",
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
    end
  end
end

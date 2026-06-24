require "test_helper"

module Aicoo
  class LearningLoopQualityReportTest < ActiveSupport::TestCase
    setup do
      ActionResult.delete_all
      ActionPredictionCalibrationLog.delete_all
    end

    test "calculates accuracy score from profit error" do
      create_result(predicted: 10_000, actual: 8_000, action_type: "seo_article")

      report = LearningLoopQualityReport.new.call

      assert_equal 1, report.total_evaluated
      assert_equal 80, report.prediction_accuracy_score
      assert_equal 0.2.to_d, report.profit_error_rate
    end

    test "calculates learning trend" do
      create_result(predicted: 10_000, actual: 2_000, action_type: "seo_article", evaluated_on: 45.days.ago.to_date)
      create_result(predicted: 10_000, actual: 9_000, action_type: "seo_article", evaluated_on: Date.current)

      report = LearningLoopQualityReport.new.call

      assert_equal "improving", report.learning_trend
    end

    test "calculates strongest and weakest action types" do
      2.times { create_result(predicted: 10_000, actual: 9_000, action_type: "seo_article") }
      2.times { create_result(predicted: 10_000, actual: 1_000, action_type: "build_lp") }

      report = LearningLoopQualityReport.new.call

      assert_equal "seo_article", report.strongest_action_types.first.action_type
      assert_equal "build_lp", report.weakest_action_types.first.action_type
    end

    test "ranks overestimated and underestimated actions" do
      over = create_result(predicted: 10_000, actual: 1_000, action_type: "seo_article", title: "Overestimated action")
      under = create_result(predicted: 1_000, actual: 10_000, action_type: "build_lp", title: "Underestimated action")

      report = LearningLoopQualityReport.new.call

      assert_equal over.action_candidate.title, report.most_overestimated_actions.first.title
      assert_equal under.action_candidate.title, report.most_underestimated_actions.first.title
    end

    test "calculates calibration effectiveness from calibration logs" do
      create_calibration_log(error_rate: 0.6, calculated_at: 2.days.ago)
      create_calibration_log(error_rate: 0.3, calculated_at: Time.current)

      report = LearningLoopQualityReport.new.call

      assert_equal 50, report.calibration_effectiveness_score
    end

    private

    def create_result(predicted:, actual:, action_type:, evaluated_on: Date.current, title: nil)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: title || "Quality report #{action_type} #{SecureRandom.hex(4)}",
        action_type:,
        status: "done",
        immediate_value_yen: predicted,
        success_probability: 0.8,
        expected_hours: 1
      )
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: evaluated_on,
        evaluated_on:,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: predicted,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end

    def create_calibration_log(error_rate:, calculated_at:)
      ActionPredictionCalibrationLog.create!(
        action_type: "seo_article",
        old_profit_calibration_factor: 1,
        new_profit_calibration_factor: 1,
        old_probability_calibration_factor: 1,
        new_probability_calibration_factor: 1,
        sample_count: 10,
        avg_profit_error_rate: error_rate,
        calculated_at:,
        source: "manual"
      )
    end
  end
end

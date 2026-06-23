require "test_helper"

module Aicoo
  class CalibrationEngineTest < ActiveSupport::TestCase
    setup do
      ActionPredictionCalibrationLog.delete_all
      ActionPredictionCalibration.delete_all
    end

    test "aggregates action results by action type" do
      create_results(action_type: "seo_article", count: 10, predicted_profit: 1_000, actual_profit: 500)
      create_results(action_type: "build_lp", count: 10, predicted_profit: 2_000, actual_profit: 4_000)

      result = CalibrationEngine.run!

      assert_equal 2, result.calibration_count
      assert_equal 10, ActionPredictionCalibration.find_by!(action_type: "seo_article").sample_count
      assert_equal 10, ActionPredictionCalibration.find_by!(action_type: "build_lp").sample_count
    end

    test "keeps factors at one below minimum sample size" do
      create_results(action_type: "seo_improvement", count: 3, predicted_profit: 1_000, actual_profit: 100)

      CalibrationEngine.run!
      calibration = ActionPredictionCalibration.find_by!(action_type: "seo_improvement")

      assert_equal 3, calibration.sample_count
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert_equal 1.to_d, calibration.probability_calibration_factor
    end

    test "calculates factors when enough samples exist" do
      create_results(action_type: "market_research", count: 10, predicted_profit: 1_000, actual_profit: 500, predicted_probability: 0.5)

      CalibrationEngine.run!
      calibration = ActionPredictionCalibration.find_by!(action_type: "market_research")

      assert_equal 10, calibration.sample_count
      assert_equal 0.5.to_d, calibration.profit_calibration_factor
      assert_equal 2.to_d, calibration.probability_calibration_factor
      assert_equal 1, ActionPredictionCalibrationLog.where(action_type: "market_research").count
    end

    test "clips factors between point one and three" do
      create_results(action_type: "automation", count: 10, predicted_profit: 100, actual_profit: 2_000, predicted_probability: 0.01)
      create_results(action_type: "outsourcing", count: 10, predicted_profit: 1_000, actual_profit: 1, predicted_probability: 0.8)

      CalibrationEngine.run!

      assert_equal 3.to_d, ActionPredictionCalibration.find_by!(action_type: "automation").profit_calibration_factor
      assert_equal 3.to_d, ActionPredictionCalibration.find_by!(action_type: "automation").probability_calibration_factor
      assert_equal 0.1.to_d, ActionPredictionCalibration.find_by!(action_type: "outsourcing").profit_calibration_factor
    end

    test "does not crash on zero division" do
      create_results(action_type: "pivot", count: 10, predicted_profit: 0, actual_profit: 500, predicted_probability: 0)

      assert_nothing_raised { CalibrationEngine.run! }
      calibration = ActionPredictionCalibration.find_by!(action_type: "pivot")
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert_equal 1.to_d, calibration.probability_calibration_factor
    end

    private

    def create_results(action_type:, count:, predicted_profit:, actual_profit:, predicted_probability: 0.5)
      count.times do |index|
        candidate = ActionCandidate.create!(
          business: businesses(:suelog),
          title: "#{action_type} candidate #{SecureRandom.hex(4)}",
          action_type:,
          immediate_value_yen: predicted_profit,
          success_probability: predicted_probability,
          expected_hours: 1
        )

        ActionResult.create!(
          action_candidate: candidate,
          business: candidate.business,
          executed_on: Date.current - 10.days + index.days,
          evaluated_on: Date.current,
          predicted_expected_profit_yen: predicted_profit,
          predicted_success_probability: predicted_probability,
          actual_profit_yen: actual_profit,
          actual_revenue_yen: actual_profit,
          evaluation_status: "evaluated"
        )
      end
    end
  end
end

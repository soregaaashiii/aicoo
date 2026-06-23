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
      create_results(action_type: "market_research", count: 10, predicted_profit: 1_000, actual_profit: 900, predicted_probability: 0.9)

      CalibrationEngine.run!
      calibration = ActionPredictionCalibration.find_by!(action_type: "market_research")

      assert_equal 10, calibration.sample_count
      assert_equal 0.9.to_d, calibration.profit_calibration_factor
      assert_in_delta 1.111, calibration.probability_calibration_factor.to_f, 0.001
      assert_equal "auto_applied", calibration.approval_status
      assert_equal 1, ActionPredictionCalibrationLog.where(action_type: "market_research").count
    end

    test "sets confidence and warning metadata" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1.0,
        probability_calibration_factor: 1.0
      )
      create_results(action_type: "seo_article", count: 10, predicted_profit: 1_000, actual_profit: 2_000)

      CalibrationEngine.run!
      calibration = ActionPredictionCalibration.find_by!(action_type: "seo_article")

      assert_equal "medium", calibration.confidence_level
      assert_equal "warning", calibration.warning_level
      assert_includes calibration.warning_reason, "前回比50%以上"
      assert_equal 1.to_d, calibration.previous_profit_calibration_factor
      assert_equal "pending", calibration.approval_status
      assert_equal 2.to_d, calibration.pending_profit_calibration_factor
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert calibration.factor_changed_at.present?
    end

    test "clips factors between point one and three" do
      create_results(action_type: "automation", count: 10, predicted_profit: 100, actual_profit: 2_000, predicted_probability: 0.01)
      create_results(action_type: "outsourcing", count: 10, predicted_profit: 1_000, actual_profit: 1, predicted_probability: 0.8)

      CalibrationEngine.run!

      automation = ActionPredictionCalibration.find_by!(action_type: "automation")
      assert_equal 1.to_d, automation.profit_calibration_factor
      assert_equal 3.to_d, automation.pending_profit_calibration_factor
      assert_equal 3.to_d, automation.pending_probability_calibration_factor
      assert_equal "danger", automation.warning_level
      assert_equal "pending", automation.approval_status
      assert_equal 1.to_d, ActionPredictionCalibration.find_by!(action_type: "outsourcing").profit_calibration_factor
      assert_equal 0.1.to_d, ActionPredictionCalibration.find_by!(action_type: "outsourcing").pending_profit_calibration_factor
    end

    test "low confidence calibration goes to approval queue" do
      create_results(action_type: "sales", count: 3, predicted_profit: 1_000, actual_profit: 900)

      CalibrationEngine.run!
      calibration = ActionPredictionCalibration.find_by!(action_type: "sales")

      assert_equal "low", calibration.confidence_level
      assert_equal "pending", calibration.approval_status
      assert_equal 1.to_d, calibration.profit_calibration_factor
      assert_equal 1.to_d, calibration.pending_profit_calibration_factor
      assert_includes calibration.warning_reason, "信頼度がlow"
    end

    test "approval applies pending factors and rejection keeps active factors" do
      calibration = ActionPredictionCalibration.create!(
        action_type: "build_mvp",
        sample_count: 10,
        profit_calibration_factor: 1.0,
        probability_calibration_factor: 1.0,
        pending_profit_calibration_factor: 0.5,
        pending_probability_calibration_factor: 0.8,
        approval_status: "pending",
        approval_requested_at: Time.current
      )

      calibration.approve!(note: "looks good")
      assert_equal "approved", calibration.approval_status
      assert_equal 0.5.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "approval", ActionPredictionCalibrationLog.last.source

      calibration.update!(
        pending_profit_calibration_factor: 0.2,
        pending_probability_calibration_factor: 0.7,
        approval_status: "pending",
        approval_requested_at: Time.current
      )
      calibration.reject!(note: "too aggressive")
      assert_equal "rejected", calibration.approval_status
      assert_equal 0.5.to_d, calibration.profit_calibration_factor
      assert_nil calibration.pending_profit_calibration_factor
      assert_equal "rejected", ActionPredictionCalibrationLog.last.source
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

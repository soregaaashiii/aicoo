require "test_helper"

module Aicoo
  class LearningReportRecommendationTest < ActiveSupport::TestCase
    setup do
      ActionResult.delete_all
      ActionExecution.delete_all
      ActionPredictionCalibrationLog.delete_all
    end

    test "registration rate below 90 creates collect more results recommendation" do
      execution = create_completed_execution
      create_result(execution:)
      create_completed_execution

      recommendation = LearningReportRecommendation.new.call.recommendations.find { |item| item.category == "collect_more_results" }

      assert recommendation
      assert_equal "critical", recommendation.priority
      assert_match "ActionResult登録", recommendation.title
    end

    test "overestimated action creates reduce overestimation recommendation" do
      create_result(predicted: 10_000, actual: 1_000, action_type: "seo_article")

      recommendation = LearningReportRecommendation.new.call.recommendations.find { |item| item.category == "reduce_overestimation" }

      assert recommendation
      assert_equal "high", recommendation.priority
      assert_match "予測利益", recommendation.reason
    end

    test "underestimated action creates review underestimation recommendation" do
      create_result(predicted: 1_000, actual: 10_000, action_type: "ui_improvement")

      recommendation = LearningReportRecommendation.new.call.recommendations.find { |item| item.category == "review_underestimation" }

      assert recommendation
      assert_equal "medium", recommendation.priority
      assert_match "過小評価", recommendation.recommended_action
    end

    test "discovery source performance creates recommendation" do
      create_opportunity_result(source_type: "owner_discovery", actual: 10_000)
      create_opportunity_result(source_type: "owner_discovery", actual: 12_000)

      recommendation = LearningReportRecommendation.new.call.recommendations.find { |item| item.category == "discovery_source" }

      assert recommendation
      assert_match "owner_discovery", recommendation.title
      assert_equal Rails.application.routes.url_helpers.owner_discovery_report_path, recommendation.target_path
    end

    private

    def create_completed_execution
      candidate = create_candidate(action_type: "seo_article")
      candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: Time.current,
        result_summary: "done"
      )
    end

    def create_result(predicted: 10_000, actual: 8_000, action_type: "seo_article", execution: nil)
      candidate = execution&.action_candidate || create_candidate(action_type:, predicted:)
      ActionResult.create!(
        action_execution: execution,
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: predicted,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end

    def create_candidate(action_type:, predicted: 10_000)
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Recommendation #{action_type} #{SecureRandom.hex(4)}",
        action_type:,
        status: "done",
        immediate_value_yen: predicted,
        success_probability: 0.8,
        expected_hours: 1
      )
    end

    def create_opportunity_result(source_type:, actual:)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "#{source_type} recommendation opportunity #{SecureRandom.hex(4)}",
        source_type:,
        business: businesses(:suelog)
      )
      candidate = opportunity.convert_to_action_candidate!
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: 10_000,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end
  end
end

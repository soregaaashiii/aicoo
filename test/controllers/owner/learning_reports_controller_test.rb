require "test_helper"

module Owner
  class LearningReportsControllerTest < ActionDispatch::IntegrationTest
    test "shows learning loop quality report" do
      get owner_learning_report_url

      assert_response :success
      assert_includes response.body, "学習品質レポート"
      assert_includes response.body, "Summary"
      assert_includes response.body, "Recommendations"
      assert_includes response.body, "Decision Log Summary"
      assert_includes response.body, "Strategic Learning"
      assert_includes response.body, "Strategic Learning Guardrail"
      assert_includes response.body, "思想一致率"
      assert_includes response.body, "最大Boost"
      assert_includes response.body, "Practicality分析"
      assert_includes response.body, "Evidence分析"
      assert_includes response.body, "ActionCandidate化"
      assert_includes response.body, "Accuracy"
      assert_includes response.body, "Calibration"
      assert_includes response.body, "Action Types"
      assert_includes response.body, "Discovery Source Recommendations"
      assert_includes response.body, "Overestimated"
      assert_includes response.body, "Underestimated"
      assert_includes response.body, "Warnings"
    end
  end
end

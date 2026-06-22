require "test_helper"

class DepartmentEvaluationTuningCandidateGeneratorTest < ActiveSupport::TestCase
  test "generates revenue tuning candidate when actual profit underperforms prediction" do
    create_result(department: "revenue", predicted: 100_000, actual: 20_000)

    result = DepartmentEvaluationTuningCandidateGenerator.new.call

    candidate = result.created.find { |action_candidate| action_candidate.metadata["target_department"] == "revenue" }
    assert candidate
    assert_equal "evaluation_tuning", candidate.action_type
    assert_equal "lab", candidate.department
    assert_includes candidate.title, "Revenue評価式"
    assert_includes candidate.execution_prompt, "成功確率"
  end

  test "generates lab tuning candidate when success rate is low" do
    create_result(department: "lab", predicted: 10_000, actual: -10_000)

    result = DepartmentEvaluationTuningCandidateGenerator.new.call

    candidate = result.created.find { |action_candidate| action_candidate.metadata["target_department"] == "lab" }
    assert candidate
    assert_equal "evaluation_tuning", candidate.action_type
    assert_includes candidate.title, "学習価値"
  end

  test "generates new business tuning candidate when prediction gap is large" do
    create_result(department: "new_business", predicted: 80_000, actual: 10_000)

    result = DepartmentEvaluationTuningCandidateGenerator.new.call

    candidate = result.created.find { |action_candidate| action_candidate.metadata["target_department"] == "new_business" }
    assert candidate
    assert_equal "evaluation_tuning", candidate.action_type
    assert_includes candidate.title, "市場規模"
    assert_includes candidate.execution_prompt, "自動化率"
  end

  test "does not generate duplicate tuning candidate within seven days" do
    result = create_result(department: "revenue", predicted: 100_000, actual: 20_000)
    result.business.action_candidates.create!(
      title: "Revenue評価式の成功確率を保守的に補正する",
      action_type: "evaluation_tuning",
      department: "lab",
      generation_source: "ai_reevaluation",
      immediate_value_yen: 0,
      success_probability: 0.7,
      metadata: { "target_department" => "revenue" }
    )

    generator_result = DepartmentEvaluationTuningCandidateGenerator.new.call

    assert_empty generator_result.created
    assert_includes generator_result.skipped.join("\n"), "duplicate"
  end

  private

  def create_result(department:, predicted:, actual:)
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "#{department} tuning source",
      action_type: "other",
      department:,
      generation_source: "manual",
      immediate_value_yen: predicted,
      success_probability: 1,
      confidence_score: 70
    )
    ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: 8.days.ago.to_date,
      evaluated_on: Date.current,
      predicted_expected_profit_yen: predicted,
      actual_profit_yen: actual,
      evaluation_status: "evaluated"
    )
  end
end

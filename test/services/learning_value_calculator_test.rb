require "test_helper"

class LearningValueCalculatorTest < ActiveSupport::TestCase
  test "assigns learning value to data preparation and judge learning actions" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "ActionResultを記録してJudge補正を再開する",
      action_type: "data_preparation",
      immediate_value_yen: 0,
      success_probability: 0.5,
      expected_hours: 1,
      data_confidence_score: 20,
      metadata: { "metric_rule" => "correction_readiness" }
    )

    assert_operator action_candidate.expected_learning_value_yen, :>, 0
    assert_equal action_candidate.expected_revenue_value_yen + action_candidate.expected_learning_value_yen,
                 action_candidate.expected_total_value_yen
  end

  test "revenue and learning ratios add up to 100 when total value exists" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "LP検証で収益と学習を両方得る",
      action_type: "build_lp",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      data_confidence_score: 80
    )

    assert_equal 100, action_candidate.revenue_ratio + action_candidate.learning_ratio
  end
end

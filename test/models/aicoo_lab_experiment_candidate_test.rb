require "test_helper"

class AicooLabExperimentCandidateTest < ActiveSupport::TestCase
  test "builds a candidate from template and calculates scores" do
    candidate = AicooLabExperimentCandidate.from_template("low_cost_lp")
    candidate.save!

    assert_equal "lp", candidate.experiment_type
    assert_equal "proposed", candidate.status
    assert candidate.expected_value_score.positive?
    assert candidate.lab_priority_score.positive?
  end

  test "converts candidate to experiment" do
    candidate = AicooLabExperimentCandidate.create!(
      title: "Candidate conversion",
      experiment_type: "lp",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 40_000,
      success_probability: 0.3,
      budget_yen: 1_000,
      estimated_work_minutes: 120,
      rationale: "Good candidate",
      target_user: "Target user",
      problem_statement: "Problem statement",
      hypothesis: "Hypothesis text",
      validation_method: "Validation method",
      expected_learning: "Expected learning",
      rejection_condition: "Rejection condition"
    )

    assert_difference("AicooLabExperiment.count") do
      experiment = candidate.convert_to_experiment!

      assert_equal "converted", candidate.status
      assert_equal experiment, candidate.converted_experiment
      assert_equal candidate.title, experiment.title
      assert_includes experiment.description, "Target user: Target user"
      assert_includes experiment.description, "Problem: Problem statement"
      assert_includes experiment.description, "Hypothesis: Hypothesis text"
      assert_includes experiment.description, "Validation method: Validation method"
      assert_includes experiment.notes, "Good candidate"
      assert_includes experiment.notes, "Expected learning: Expected learning"
      assert_includes experiment.notes, "Rejection condition: Rejection condition"
    end
  end

  test "approve creates and links a business" do
    candidate = AicooLabExperimentCandidate.create!(
      title: "Model approve business",
      experiment_type: "lp",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 40_000,
      success_probability: 0.3,
      budget_yen: 1_000,
      estimated_work_minutes: 120,
      description: "Business description",
      target_user: "Target user",
      problem_statement: "Problem statement",
      hypothesis: "Hypothesis text",
      validation_method: "Validation method"
    )

    assert_difference("Business.count", 1) do
      business = candidate.approve!
      assert_equal "Model approve business", business.name
      assert_equal "idea", business.status
    end

    assert_equal "approved", candidate.reload.status
    assert_equal "Model approve business", candidate.business.name
    assert_includes candidate.business.description, "Problem statement"
  end

  test "approve reuses linked business and avoids duplicate creation" do
    business = Business.create!(name: "Linked business", status: "launched")
    candidate = AicooLabExperimentCandidate.create!(
      title: "Different candidate title",
      business:,
      experiment_type: "lp",
      acquisition_channel: "seo"
    )

    assert_no_difference("Business.count") do
      assert_equal business, candidate.approve!
    end

    assert_equal business, candidate.reload.business
  end
end

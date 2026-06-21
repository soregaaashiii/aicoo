require "test_helper"

class AicooLabExperimentTest < ActiveSupport::TestCase
  test "calculates lab scores before save" do
    AicooLabSetting.current.update!(hourly_cost_yen: 1_200)

    experiment = AicooLabExperiment.create!(
      title: "LP smoke test",
      experiment_type: "lp",
      acquisition_channel: "ads",
      expected_90d_profit_yen: 90_000,
      success_probability: 0.5,
      budget_yen: 3_000,
      estimated_work_minutes: 60
    )

    assert_in_delta (45_000.to_d / 4_200), experiment.expected_value_score, 0.0001
    assert_in_delta (1.to_d / 30), experiment.scoring_speed_score, 0.0001
    assert_in_delta (45_000.to_d / 4_200 / 30), experiment.lab_priority_score, 0.0001
  end

  test "running status sets score due dates" do
    experiment = AicooLabExperiment.create!(title: "Running test", experiment_type: "lp", acquisition_channel: "seo")

    experiment.mark_status!("running")

    assert_equal "running", experiment.status
    assert_not_nil experiment.started_at
    assert_not_nil experiment.published_at
    assert_not_nil experiment.score_due_7d_at
    assert_not_nil experiment.score_due_30d_at
    assert_not_nil experiment.score_due_90d_at
  end
end

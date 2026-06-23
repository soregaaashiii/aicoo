require "test_helper"

class ActionPredictionCalibrationImpactTest < ActiveSupport::TestCase
  setup do
    ActionPredictionCalibration.delete_all
  end

  test "shows ranking movement caused by prediction calibration" do
    ActionPredictionCalibration.create!(
      action_type: "seo_article",
      sample_count: 10,
      profit_calibration_factor: 3.0,
      probability_calibration_factor: 1.0
    )

    boosted = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "補正で上がるSEO候補",
      action_type: "seo_article",
      immediate_value_yen: 1_000,
      success_probability: 1.0,
      expected_hours: 1
    )
    baseline = ActionCandidate.create!(
      business: businesses(:cards),
      title: "補正なし候補",
      action_type: "market_research",
      immediate_value_yen: 1_500,
      success_probability: 1.0,
      expected_hours: 1
    )

    impact = ActionPredictionCalibrationImpact.new(scope: ActionCandidate.where(id: [ boosted.id, baseline.id ])).call

    assert_equal boosted, impact.largest_rank_up.action_candidate
    assert_equal 1, impact.largest_rank_up.rank_delta
    assert_equal baseline, impact.largest_rank_down.action_candidate
    assert_equal(-1, impact.largest_rank_down.rank_delta)
    assert_equal 2, impact.changed_count
    assert impact.action_type_changes.any? { |change| change.action_type == "seo_article" }
  end
end

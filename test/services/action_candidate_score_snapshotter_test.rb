require "test_helper"

class ActionCandidateScoreSnapshotterTest < ActiveSupport::TestCase
  test "creates snapshots with raw and adjusted ranks" do
    high_raw_bad = create_candidate(title: "High raw bad", generation_source: "manual", action_type: "ui_improvement", value: 20_000)
    low_raw_good = create_candidate(title: "Low raw good", generation_source: "ai_business", action_type: "seo_improvement", value: 12_000)
    create_result_for(high_raw_bad, actual: -20_000)
    create_result_for(low_raw_good, actual: 12_000)

    result = ActionCandidateScoreSnapshotter.new.snapshot!(date: Date.new(2026, 6, 21))

    high_snapshot = ActionCandidateScoreSnapshot.find_by!(action_candidate: high_raw_bad)
    low_snapshot = ActionCandidateScoreSnapshot.find_by!(action_candidate: low_raw_good)
    assert_equal ActionCandidate.active_for_ranking.count, result.snapshots.size
    assert_operator low_snapshot.rank_delta, :>, 0
    assert_operator high_snapshot.rank_delta, :<, 0
    assert_equal "Judge補正で順位上昇", low_snapshot.reason
    assert_equal "Judge補正で順位低下", high_snapshot.reason
  end

  test "does not create duplicate snapshots for same candidate and date" do
    create_candidate(title: "No duplicate", generation_source: "ai_cross_business", action_type: "sales", value: 10_000)
    snapshotter = ActionCandidateScoreSnapshotter.new

    assert_difference("ActionCandidateScoreSnapshot.count", ActionCandidate.active_for_ranking.count) do
      snapshotter.snapshot!(date: Date.new(2026, 6, 21))
    end
    assert_no_difference("ActionCandidateScoreSnapshot.count") do
      snapshotter.snapshot!(date: Date.new(2026, 6, 21))
    end
  end

  test "records no adjustment reason when judge data is missing" do
    candidate = create_candidate(title: "No judge data", generation_source: "ai_cross_business", action_type: "sales", value: 10_000)

    ActionCandidateScoreSnapshotter.new.snapshot!(date: Date.new(2026, 6, 21))

    snapshot = ActionCandidateScoreSnapshot.find_by!(action_candidate: candidate)
    assert_equal "データ不足で補正なし", snapshot.reason
    assert_equal 1.to_d, snapshot.adjustment_multiplier
  end

  private

  def create_candidate(title:, generation_source:, action_type:, value:)
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type:,
      generation_source:,
      immediate_value_yen: value,
      success_probability: 1,
      expected_hours: 1,
      status: "idea"
    )
  end

  def create_result_for(action_candidate, actual:)
    ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current - 10,
      evaluated_on: Date.current,
      actual_profit_yen: actual,
      evaluation_status: "evaluated"
    )
  end
end

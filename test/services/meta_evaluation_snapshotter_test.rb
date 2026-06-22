require "test_helper"

class MetaEvaluationSnapshotterTest < ActiveSupport::TestCase
  test "creates snapshots from evaluator breakdown" do
    business = businesses(:suelog)
    create_candidate(business:, gsc_confidence: 80, gsc_expected_value: 10_000)
    create_candidate(business:, gsc_confidence: 40, gsc_expected_value: 20_000)

    result = MetaEvaluationSnapshotter.new.snapshot!(date: Date.new(2026, 6, 21))

    assert_equal (Business.count + 1) * 5, result.snapshots.size
    gsc = MetaEvaluationSnapshot.global.find_by!(recorded_on: Date.new(2026, 6, 21), evaluator_type: "gsc")
    assert_equal 2, gsc.candidate_count
    assert_equal 15_000, gsc.average_expected_value_yen
    assert_equal 60, gsc.average_confidence_score
    assert_equal 9_000, gsc.weighted_contribution_score
  end

  test "does not duplicate snapshots for same date business and evaluator" do
    business = businesses(:suelog)
    create_candidate(business:)
    date = Date.new(2026, 6, 21)

    assert_difference("MetaEvaluationSnapshot.count", (Business.count + 1) * 5) do
      MetaEvaluationSnapshotter.new.snapshot!(date:)
    end

    assert_no_difference("MetaEvaluationSnapshot.count") do
      MetaEvaluationSnapshotter.new.snapshot!(date:)
    end
  end

  test "snapshots business scope" do
    business = businesses(:suelog)
    create_candidate(business:, gsc_confidence: 70)

    snapshots = MetaEvaluationSnapshotter.new.snapshot_business!(business:, date: Date.new(2026, 6, 21))

    assert_equal 5, snapshots.size
    assert snapshots.all? { |snapshot| snapshot.business == business }
  end

  private

  def create_candidate(business:, gsc_confidence: 50, gsc_expected_value: 10_000)
    candidate = ActionCandidate.create!(
      business:,
      title: "Meta snapshot candidate #{SecureRandom.hex(4)}",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 1_000,
      success_probability: 1,
      expected_hours: 1
    )
    candidate.update_columns(
      metadata: {
        "evaluator_breakdown" => [
          { "evaluator_type" => "gsc", "expected_value_yen" => gsc_expected_value, "confidence_score" => gsc_confidence, "reason" => "GSC reason" },
          { "evaluator_type" => "ga4", "expected_value_yen" => 5_000, "confidence_score" => 30, "reason" => "GA4 reason" },
          { "evaluator_type" => "judge", "expected_value_yen" => 8_000, "confidence_score" => 20, "reason" => "Judge reason" },
          { "evaluator_type" => "revenue", "expected_value_yen" => 0, "confidence_score" => 0, "reason" => "Revenue reason" },
          { "evaluator_type" => "learning", "expected_value_yen" => 6_000, "confidence_score" => 40, "reason" => "Learning reason" }
        ]
      }
    )
    candidate
  end
end

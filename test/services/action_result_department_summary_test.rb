require "test_helper"

class ActionResultDepartmentSummaryTest < ActiveSupport::TestCase
  test "summarizes evaluated action results by department" do
    revenue = create_result(department: "revenue", predicted: 10_000, actual: 12_000, confidence: 80)
    lab = create_result(department: "lab", predicted: 5_000, actual: 1_000, confidence: 60)
    create_result(department: "general", predicted: 100_000, actual: 100_000, confidence: 100)

    summaries = ActionResultDepartmentSummary.new.summaries.index_by(&:department)

    assert_equal 1, summaries.fetch("revenue").executed_count
    assert_equal 1, summaries.fetch("revenue").success_count
    assert_equal 10_000, summaries.fetch("revenue").predicted_expected_profit_total_yen
    assert_equal 12_000, summaries.fetch("revenue").actual_profit_total_yen
    assert_equal 2_000, summaries.fetch("revenue").prediction_gap_yen
    assert_equal 80.to_d, summaries.fetch("revenue").average_confidence_score

    assert_equal 1, summaries.fetch("lab").executed_count
    assert_equal lab.predicted_expected_profit_yen, summaries.fetch("lab").predicted_expected_profit_total_yen
    assert_not_includes summaries.keys, "general"
    assert_equal revenue.actual_profit_yen, summaries.fetch("revenue").actual_profit_total_yen
  end

  test "handles departments with no action results" do
    summaries = ActionResultDepartmentSummary.new(scope: ActionResult.none).summaries

    assert_equal %w[revenue lab new_business], summaries.map(&:department)
    assert summaries.all? { |summary| summary.executed_count.zero? }
    assert summaries.all? { |summary| summary.success_rate.nil? }
  end

  private

  def create_result(department:, predicted:, actual:, confidence:)
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "#{department} result action",
      action_type: "other",
      department:,
      generation_source: "manual",
      immediate_value_yen: predicted,
      success_probability: 1,
      confidence_score: confidence
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

require "test_helper"

class AicooExecutionFeasibilityCorrectionOverviewServiceTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @other_business = businesses(:cards)
  end

  test "counts corrected candidates" do
    create_candidate(label: "over_sized", applied: true)
    create_candidate(label: "insufficient_data", applied: false)

    summary = AicooExecutionFeasibilityCorrectionOverviewService.new(scope: overview_scope).call.fetch(:overall)

    assert_equal 2, summary.total_candidates
    assert_equal 1, summary.corrected_count
    assert_equal 0.5.to_d, summary.correction_rate
    assert_equal 1, summary.labels_count.fetch("over_sized")
    assert_equal 1, summary.labels_count.fetch("insufficient_data")
  end

  test "summarizes correction rate by action type" do
    create_candidate(action_type: "seo_improvement", label: "over_sized", applied: true)
    create_candidate(action_type: "seo_improvement", label: "hard_to_execute", applied: true)
    create_candidate(action_type: "sales", label: "insufficient_data", applied: false)

    result = AicooExecutionFeasibilityCorrectionOverviewService.new(scope: overview_scope).call
    seo_summary = result.fetch(:by_action_type).find { |summary| summary.key == "seo_improvement" }

    assert_equal 2, seo_summary.total_candidates
    assert_equal 2, seo_summary.corrected_count
    assert_equal 1.to_d, seo_summary.correction_rate
  end

  test "summarizes correction rate by business" do
    create_candidate(business: @business, label: "over_sized", applied: true)
    create_candidate(business: @business, label: "insufficient_data", applied: false)
    create_candidate(business: @other_business, label: "hard_to_execute", applied: true)

    result = AicooExecutionFeasibilityCorrectionOverviewService.new(scope: overview_scope).call
    business_summary = result.fetch(:by_business).find { |summary| summary.key == @business.id }

    assert_equal 2, business_summary.total_candidates
    assert_equal 1, business_summary.corrected_count
    assert_equal 0.5.to_d, business_summary.correction_rate
  end

  test "calculates average deltas" do
    create_candidate(label: "over_sized", applied: true, base_probability: "0.60", adjusted_probability: "0.52", base_hours: "2.0", adjusted_hours: "2.4")
    create_candidate(label: "hard_to_execute", applied: true, base_probability: "0.50", adjusted_probability: "0.35", base_hours: "4.0", adjusted_hours: "5.4")

    summary = AicooExecutionFeasibilityCorrectionOverviewService.new(scope: overview_scope).call.fetch(:overall)

    assert_equal(-0.115.to_d, summary.average_success_probability_delta)
    assert_equal 0.9.to_d, summary.average_expected_hours_delta
  end

  test "does not break when metadata is empty" do
    ActionCandidate.create!(
      business: @business,
      title: "Overview empty metadata",
      action_type: "other",
      immediate_value_yen: 1_000,
      success_probability: 0.3,
      metadata: {}
    )

    summary = AicooExecutionFeasibilityCorrectionOverviewService.new(scope: overview_scope).call.fetch(:overall)

    assert_equal 1, summary.total_candidates
    assert_equal 0, summary.corrected_count
    assert_equal 1, summary.labels_count.fetch("insufficient_data")
  end

  private

  def overview_scope
    ActionCandidate.where("title LIKE ?", "Overview%")
  end

  def create_candidate(
    business: @business,
    action_type: "seo_improvement",
    label:,
    applied:,
    base_probability: "0.60",
    adjusted_probability: "0.52",
    base_hours: "2.0",
    adjusted_hours: "2.4"
  )
    action_candidate = ActionCandidate.create!(
      business:,
      title: "Overview #{SecureRandom.hex(4)}",
      action_type:,
      immediate_value_yen: 1_000,
      success_probability: 0.3
    )
    action_candidate.update_columns(
      metadata: {
        "execution_feasibility_correction" => {
          "applied" => applied,
          "feasibility_label" => label,
          "base_success_probability" => base_probability,
          "adjusted_success_probability" => adjusted_probability,
          "base_expected_hours" => base_hours,
          "adjusted_expected_hours" => adjusted_hours,
          "reason" => "#{label} reason"
        }
      }
    )
    action_candidate
  end
end

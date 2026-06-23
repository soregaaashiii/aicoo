require "test_helper"

class AicooExecutionFeasibilityCorrectionServiceTest < ActiveSupport::TestCase
  setup do
    ActionExecutionLog.delete_all
    @business = businesses(:suelog)
  end

  test "does not correct when data is insufficient" do
    action_candidate = build_candidate(success_probability: 0.6, expected_hours: 2)

    AicooExecutionFeasibilityCorrectionService.new(action_candidate).apply!

    assert_equal 0.6.to_d, action_candidate.success_probability
    assert_equal 2.to_d, action_candidate.expected_hours
    assert_equal false, action_candidate.metadata.dig("execution_feasibility_correction", "applied")
  end

  test "over sized lowers success probability and shrinks prompt quantity" do
    seed_logs(status: "partial", planned: 500, actual: 250)
    action_candidate = build_candidate(
      success_probability: 0.6,
      expected_hours: 2,
      execution_prompt: "梅田店舗を500件追加してください。"
    )

    AicooExecutionFeasibilityCorrectionService.new(action_candidate).apply!

    assert_equal 0.52.to_d, action_candidate.success_probability
    assert_equal 2.4.to_d, action_candidate.expected_hours
    assert_includes action_candidate.execution_prompt, "250件"
    assert_includes action_candidate.evaluation_reason, "数量を保守化"
    assert_equal "over_sized", action_candidate.metadata.dig("execution_feasibility_correction", "feasibility_label")
  end

  test "hard to execute increases expected hours and lowers success probability" do
    seed_logs(status: "failed", planned: 10, actual: 0)
    seed_logs(status: "skipped", planned: 10, actual: 0)
    seed_logs(status: "completed", planned: 10, actual: 10)
    action_candidate = build_candidate(success_probability: 0.6, expected_hours: 2)

    AicooExecutionFeasibilityCorrectionService.new(action_candidate).apply!

    assert_equal 0.45.to_d, action_candidate.success_probability
    assert_equal 2.7.to_d, action_candidate.expected_hours
    assert_includes action_candidate.evaluation_reason, "実行失敗"
  end

  test "easy to execute only lightly changes success probability" do
    seed_logs(status: "completed", planned: 10, actual: 10)
    action_candidate = build_candidate(success_probability: 0.6, expected_hours: 2)

    AicooExecutionFeasibilityCorrectionService.new(action_candidate).apply!

    assert_equal 0.62.to_d, action_candidate.success_probability
    assert_equal 2.to_d, action_candidate.expected_hours
  end

  test "business action type summary has priority over action type summary" do
    other_business = businesses(:cards)
    seed_logs(status: "completed", planned: 10, actual: 10, business: other_business, action_type: "seo_improvement")
    seed_logs(status: "partial", planned: 10, actual: 4, business: @business, action_type: "seo_improvement")
    action_candidate = build_candidate(
      business: @business,
      action_type: "seo_improvement",
      success_probability: 0.6,
      expected_hours: 2
    )

    AicooExecutionFeasibilityCorrectionService.new(action_candidate).apply!

    assert_equal "business_action_type", action_candidate.metadata.dig("execution_feasibility_correction", "source")
    assert_equal "over_sized", action_candidate.metadata.dig("execution_feasibility_correction", "feasibility_label")
    assert_equal 0.52.to_d, action_candidate.success_probability
  end

  private

  def build_candidate(business: @business, action_type: "seo_improvement", success_probability:, expected_hours:, execution_prompt: "作業を10件実行してください。")
    ActionCandidate.new(
      business:,
      title: "実行可能性補正テスト",
      action_type:,
      immediate_value_yen: 10_000,
      success_probability:,
      expected_hours:,
      execution_prompt:,
      evaluation_reason: "初期評価"
    )
  end

  def seed_logs(status:, planned:, actual:, business: @business, action_type: "seo_improvement")
    action_candidate = ActionCandidate.create!(
      business:,
      title: "#{action_type} seed",
      action_type:,
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    3.times do
      ActionExecutionLog.create!(
        action_candidate:,
        business:,
        planned_action: "#{planned}件実行",
        planned_quantity: planned,
        actual_action: "#{actual}件実行",
        actual_quantity: actual,
        status:
      )
    end
  end
end

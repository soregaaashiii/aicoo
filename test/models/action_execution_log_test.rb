require "test_helper"

class ActionExecutionLogTest < ActiveSupport::TestCase
  test "calculates completion rate and variance quantity" do
    action_candidate = action_candidates(:nagazakicho_article)

    log = ActionExecutionLog.create!(
      action_candidate:,
      business: action_candidate.business,
      planned_action: "梅田店舗を500件追加",
      planned_quantity: 500,
      actual_action: "梅田店舗を600件追加",
      actual_quantity: 600,
      variance_reason: "想定より作業効率が高かった",
      status: "over_completed"
    )

    assert_equal BigDecimal("1.2"), log.completion_rate
    assert_equal BigDecimal("100.0"), log.variance_quantity
  end

  test "copies planned action and business from action candidate" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "梅田店舗を500件追加",
      action_type: "seo_improvement",
      execution_prompt: "吸えログへ店舗を500件追加してください。",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    log = ActionExecutionLog.create!(
      action_candidate:,
      actual_action: "梅田店舗を300件追加",
      actual_quantity: 300,
      variance_reason: "重複確認に時間がかかった"
    )

    assert_equal action_candidate.business, log.business
    assert_includes log.planned_action, "梅田店舗を500件追加"
    assert_equal BigDecimal("500.0"), log.planned_quantity
    assert_equal BigDecimal("0.6"), log.completion_rate
    assert_equal BigDecimal("-200.0"), log.variance_quantity
  end
end

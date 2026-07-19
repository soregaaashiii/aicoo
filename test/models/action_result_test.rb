require "test_helper"

class ActionResultTest < ActiveSupport::TestCase
  test "copies prediction snapshot from action candidate" do
    action_candidate = action_candidates(:nagazakicho_article)

    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )

    assert_equal action_candidate.immediate_value_yen, result.predicted_value_yen
    assert_equal action_candidate.success_probability, result.predicted_success_probability
    assert_equal action_candidate.expected_profit_yen, result.predicted_expected_profit_yen
  end

  test "calculates prediction error from actual profit" do
    action_candidate = action_candidates(:nagazakicho_article)

    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current,
      actual_profit_yen: 10_000
    )

    assert_equal 20_000, result.prediction_error_yen
    assert_in_delta BigDecimal("0.666"), result.prediction_error_rate, BigDecimal("0.001")
  end

  test "marks manual actuals when actual fields are saved directly" do
    action_candidate = action_candidates(:nagazakicho_article)

    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current,
      actual_clicks_delta: 12
    )

    assert_equal true, result.metadata["manual_actuals_recorded"]
    assert_includes result.saved_manual_actual_fields, "actual_clicks_delta"
  end

  test "marks manual actuals when metadata actual fields are saved directly" do
    action_candidate = action_candidates(:nagazakicho_article)

    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current,
      metadata: { "manual_actuals" => { "ctr" => "0.12", "average_position" => "8.4" } }
    )

    assert_equal true, result.metadata["manual_actuals_recorded"]
    assert_includes result.saved_manual_actual_fields, "ctr"
    assert_includes result.saved_manual_actual_fields, "average_position"
  end

  test "auto links to an unlinked action execution log after save" do
    action_candidate = action_candidates(:nagazakicho_article)
    log = ActionExecutionLog.create!(
      action_candidate:,
      business: action_candidate.business,
      planned_action: "梅田店舗を500件追加",
      planned_quantity: 500,
      actual_action: "梅田店舗を400件追加",
      actual_quantity: 400,
      status: "partial"
    )

    result = ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current,
      actual_profit_yen: 10_000
    )

    assert_equal result, log.reload.action_result
    assert_equal result.id, log.metadata["auto_linked_action_result_id"]
  end
end

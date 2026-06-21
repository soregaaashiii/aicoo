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
end

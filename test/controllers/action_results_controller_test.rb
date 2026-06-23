require "test_helper"

class ActionResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @action_candidate = action_candidates(:nagazakicho_article)
  end

  test "should get index" do
    get action_results_url

    assert_response :success
  end

  test "should get new" do
    get new_action_result_url(action_result: { action_candidate_id: @action_candidate.id })

    assert_response :success
  end

  test "should create action result" do
    assert_difference("ActionResult.count", 1) do
      post action_results_url, params: {
        action_result: {
          action_candidate_id: @action_candidate.id,
          business_id: @action_candidate.business_id,
          executed_on: Date.current,
          evaluated_on: Date.current,
          actual_revenue_yen: 1_000,
          actual_profit_yen: 800,
          note: "Manual result"
        }
      }
    end

    assert_redirected_to action_result_url(ActionResult.last)
  end

  test "show action candidate has result recording link" do
    get action_candidate_url(@action_candidate)

    assert_response :success
    assert_includes response.body, "実行結果を記録"
    assert_includes response.body, "売上/費用を登録"
  end

  test "show action result has revenue event link" do
    result = ActionResult.create!(
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )

    get action_result_url(result)

    assert_response :success
    assert_includes response.body, "売上/費用を登録"
    assert_includes response.body, "紐づいた売上/費用"
  end

  test "evaluate action result" do
    result = ActionResult.create!(
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )

    post evaluate_action_result_url(result)

    assert_redirected_to action_result_url(result)
    assert_includes %w[evaluated skipped], result.reload.evaluation_status
  end
end

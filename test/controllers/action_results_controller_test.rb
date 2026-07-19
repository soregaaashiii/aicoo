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

  test "new from action workspace keeps today return target" do
    get new_action_result_url(action_result: { action_candidate_id: @action_candidate.id }, return_to: owner_focus_path)

    assert_response :success
    assert_includes response.body, "Todayへ戻る"
    assert_includes response.body, "name=\"return_to\""
    assert_includes response.body, owner_focus_path
  end

  test "gets new from action execution draft" do
    execution = @action_candidate.create_action_execution!(
      status: "completed",
      execution_type: "manual",
      actual_hours: 1.5,
      actual_cost_yen: 300,
      result_summary: "実行完了",
      completed_at: Time.current
    )

    get new_action_result_url(action_execution_id: execution.id)

    assert_response :success
    assert_includes response.body, "Execution Draft"
    assert_includes response.body, "予測利益"
    assert_includes response.body, "実績時間"
    assert_includes response.body, "実行完了"
  end

  test "does not build duplicate result for same action execution" do
    execution = @action_candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
    result = ActionResult.create!(
      action_execution: execution,
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )

    get new_action_result_url(action_execution_id: execution.id)

    assert_redirected_to action_result_url(result)
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
    result = ActionResult.last
    assert_equal "evaluated", result.evaluation_status
    assert_equal true, result.metadata["manual_actuals_recorded"]
    assert_equal 800, result.actual_profit_yen
  end

  test "creates action result from action workspace and returns to today" do
    assert_difference("ActionResult.count", 1) do
      post action_results_url, params: {
        return_to: owner_focus_path,
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

    assert_redirected_to owner_focus_url
  end

  test "stores executed action expansion tasks on result" do
    @action_candidate.update_column(
      :metadata,
      {
        "action_expansion" => {
          "version" => "v1",
          "expansion_type" => "ctr_title_rewrite",
          "recommended_tasks" => [ "SEOタイトル改訂", "内部リンク追加" ],
          "task_priority" => { "SEOタイトル改訂" => 1, "内部リンク追加" => 2 },
          "confidence" => "82"
        }
      }
    )

    post action_results_url, params: {
      action_result: {
        action_candidate_id: @action_candidate.id,
        business_id: @action_candidate.business_id,
        executed_on: Date.current,
        evaluated_on: Date.current,
        actual_revenue_yen: 1_000,
        actual_profit_yen: 800,
        note: "Execution result"
      },
      executed_expansion_tasks: [ "SEOタイトル改訂" ]
    }

    learning = ActionResult.last.metadata["action_expansion_learning"]
    assert_equal [ "SEOタイトル改訂" ], learning["executed_tasks"]
    assert_equal [ "内部リンク追加" ], learning["skipped_tasks"]
    assert_equal "ctr_title_rewrite", learning["expansion_type"]
  end

  test "creates action result linked to action execution" do
    execution = @action_candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)

    assert_difference("ActionResult.count", 1) do
      post action_results_url, params: {
        action_result: {
          action_execution_id: execution.id,
          action_candidate_id: @action_candidate.id,
          business_id: @action_candidate.business_id,
          executed_on: Date.current,
          evaluated_on: Date.current,
          actual_revenue_yen: 1_000,
          actual_profit_yen: 800,
          note: "Execution result"
        }
      }
    end

    assert_redirected_to action_result_url(ActionResult.last)
    assert_equal execution, ActionResult.last.action_execution
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

require "test_helper"

class ActionExecutionLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @action_candidate = action_candidates(:nagazakicho_article)
  end

  test "should get new" do
    get new_action_execution_log_url(action_candidate_id: @action_candidate.id)

    assert_response :success
    assert_includes response.body, "実行差分を記録"
    assert_includes response.body, @action_candidate.title
  end

  test "should create action execution log" do
    assert_difference("ActionExecutionLog.count", 1) do
      post action_execution_logs_url, params: {
        action_execution_log: {
          action_candidate_id: @action_candidate.id,
          business_id: @action_candidate.business_id,
          planned_action: "梅田店舗を500件追加",
          planned_quantity: 500,
          actual_action: "梅田店舗を600件追加",
          actual_quantity: 600,
          variance_reason: "想定より作業効率が高かった",
          human_note: "追加で周辺エリアも確認した",
          status: "over_completed"
        }
      }
    end

    log = ActionExecutionLog.last
    assert_redirected_to action_execution_log_url(log)
    assert_equal @action_candidate, log.action_candidate
    assert_equal BigDecimal("1.2"), log.completion_rate
    assert_equal BigDecimal("100.0"), log.variance_quantity
  end

  test "should show action execution log" do
    log = create_log
    result = ActionResult.create!(
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )
    log.update!(
      action_result: result,
      metadata: {
        "auto_linked_action_result_id" => result.id,
        "auto_linked_at" => Time.current.iso8601,
        "auto_link_method" => "nearest_action_execution_log"
      }
    )

    get action_execution_log_url(log)

    assert_response :success
    assert_includes response.body, "提案内容"
    assert_includes response.body, "実行内容"
    assert_includes response.body, "紐づいたActionResult"
    assert_includes response.body, "自動リンク"
    assert_includes response.body, "nearest_action_execution_log"
    assert_includes response.body, "売上/費用を登録"
    assert_includes response.body, "120.0%"
  end

  test "should update action execution log" do
    log = create_log

    patch action_execution_log_url(log), params: {
      action_execution_log: {
        actual_action: "梅田店舗を300件追加",
        actual_quantity: 300,
        status: "partial"
      }
    }

    assert_redirected_to action_execution_log_url(log)
    assert_equal BigDecimal("0.6"), log.reload.completion_rate
    assert_equal BigDecimal("-200.0"), log.variance_quantity
  end

  private

  def create_log
    ActionExecutionLog.create!(
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      planned_action: "梅田店舗を500件追加",
      planned_quantity: 500,
      actual_action: "梅田店舗を600件追加",
      actual_quantity: 600,
      variance_reason: "想定より作業効率が高かった",
      status: "over_completed"
    )
  end
end

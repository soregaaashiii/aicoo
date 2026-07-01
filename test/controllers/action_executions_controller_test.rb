require "test_helper"

class ActionExecutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Execution pipeline candidate",
      action_type: "seo_improvement",
      status: "approved",
      immediate_value_yen: 10_000,
      success_probability: 0.8,
      expected_hours: 2,
      execution_prompt: "SEOタイトルを改善してください。"
    )
    @execution = @candidate.create_action_execution!(
      status: "ready",
      execution_type: "manual",
      execution_prompt: Aicoo::ExecutionPromptBuilder.new(@candidate).call
    )
  end

  test "stores prediction snapshot when created" do
    assert_equal @candidate.expected_profit_yen, @execution.predicted_profit_yen_snapshot
    assert_equal @candidate.calibrated_success_probability, @execution.predicted_success_probability_snapshot
    assert_equal @candidate.expected_hours, @execution.predicted_hours_snapshot
    assert_equal @candidate.cost_yen.to_i, @execution.predicted_cost_yen_snapshot
    assert_equal @candidate.final_score, @execution.action_score_snapshot
  end

  test "shows action execution" do
    get action_execution_url(@execution)

    assert_response :success
    assert_includes response.body, "実行準備詳細"
    assert_includes response.body, @candidate.title
    assert_includes response.body, "実行プロンプト"
    assert_includes response.body, "Prediction Snapshot"
    assert_includes response.body, "Execution Snapshot"
    assert_includes response.body, "作業開始"
    assert_includes response.body, "実行結果を入力"
    assert_includes response.body, "指示通りにできた"
    assert_includes response.body, "捗って指示以上にやった"
    assert_includes response.body, "できなくて途中で止まった"
  end

  test "starts execution" do
    assert_difference("OwnerTaskCompletionLog.count", 1) do
      patch start_action_execution_url(@execution)
    end

    assert_redirected_to action_execution_url(@execution, anchor: "execution-result-form")
    assert_equal "running", @execution.reload.status
    assert @execution.started_at.present?
    assert_equal "実行開始", OwnerTaskCompletionLog.last.action_label
  end

  test "completes execution" do
    @execution.start!

    assert_difference("OwnerTaskCompletionLog.count", 1) do
      patch complete_action_execution_url(@execution), params: {
        action_execution: {
          actual_hours: 1.5,
          actual_cost_yen: 300,
          execution_outcome: "exceeded",
          completed_task_names: [ "SEOタイトル改訂", "内部リンク追加" ],
          result_summary: "タイトルを更新した",
          extra_work: "追加でmeta descriptionも更新した"
        }
      }
    end

    assert_redirected_to action_execution_url(@execution)
    @execution.reload
    assert_equal "completed", @execution.status
    assert_equal 1.5.to_d, @execution.actual_hours
    assert_equal 300.to_d, @execution.actual_cost_yen
    assert_match "指示以上に実施", @execution.result_summary
    assert_match "タイトルを更新した", @execution.result_summary
    assert_match "追加でmeta descriptionも更新した", @execution.result_summary
    assert_equal "exceeded", @execution.metadata.dig("execution_result_intake", "execution_outcome")
    assert_equal [ "SEOタイトル改訂", "内部リンク追加" ], @execution.metadata.dig("execution_result_intake", "completed_task_names")
    assert @execution.completed_at.present?
  end

  test "shows registered action result when result exists" do
    @execution.complete!(result_summary: "完了")
    result = ActionResult.create!(
      action_execution: @execution,
      action_candidate: @candidate,
      business: @candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )

    get action_execution_url(@execution)

    assert_response :success
    assert_includes response.body, "結果登録済み"
    assert_includes response.body, action_result_path(result)
  end

  test "shows warning when completed execution has no action result" do
    @execution.update!(status: "completed", completed_at: 42.hours.ago, result_summary: "完了")

    get action_execution_url(@execution)

    assert_response :success
    assert_includes response.body, "実行結果未登録"
    assert_includes response.body, "完了から"
    assert_includes response.body, "結果登録へ進む"
  end

  test "fails execution" do
    @execution.start!

    assert_difference("OwnerTaskCompletionLog.count", 1) do
      patch fail_action_execution_url(@execution), params: {
        action_execution: {
          execution_outcome: "blocked",
          result_summary: "権限不足で失敗",
          blocked_reason: "編集権限が必要"
        }
      }
    end

    assert_redirected_to action_execution_url(@execution)
    assert_equal "failed", @execution.reload.status
    assert_match "途中で止まった", @execution.result_summary
    assert_match "権限不足で失敗", @execution.result_summary
    assert_equal "blocked", @execution.metadata.dig("execution_result_intake", "execution_outcome")
    assert_equal "編集権限が必要", @execution.metadata.dig("execution_result_intake", "blocked_reason")
    assert_equal "failed", OwnerTaskCompletionLog.last.action_result
  end
end

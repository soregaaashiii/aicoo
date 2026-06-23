require "test_helper"

class ActionCandidatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @action_candidate = action_candidates(:nagazakicho_article)
  end

  test "should get index" do
    get action_candidates_url
    assert_response :success
    assert_includes response.body, "generalのみdepartment一括分類"
  end

  test "index hides archived action candidates by default" do
    @action_candidate.update!(status: "archived")

    get action_candidates_url

    assert_response :success
    assert_not_includes response.body, @action_candidate.title
  end

  test "index can show archived action candidates with status filter" do
    @action_candidate.update!(status: "archived")

    get action_candidates_url(status: "archived")

    assert_response :success
    assert_includes response.body, @action_candidate.title
  end

  test "index can filter by department" do
    @action_candidate.update!(department: "revenue")
    other = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Lab department action",
      action_type: "data_preparation",
      department: "lab",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.4
    )

    get action_candidates_url(department: "revenue")

    assert_response :success
    assert_includes response.body, @action_candidate.title
    assert_not_includes response.body, other.title
  end

  test "index shows execution feasibility correction label" do
    @action_candidate.update_columns(
      metadata: @action_candidate.metadata.merge(
        "execution_feasibility_correction" => {
          "applied" => true,
          "feasibility_label" => "hard_to_execute",
          "reason" => "実行失敗が多い"
        }
      )
    )

    get action_candidates_url

    assert_response :success
    assert_includes response.body, "実行補正あり"
    assert_includes response.body, "hard_to_execute"
  end

  test "should get new" do
    get new_action_candidate_url
    assert_response :success
  end

  test "should create action_candidate" do
    assert_difference("ActionCandidate.count") do
      post action_candidates_url, params: { action_candidate: writable_action_candidate_params.merge(title: "新しい行動候補", department: "revenue") }
    end

    assert_redirected_to action_candidate_url(ActionCandidate.last)
    assert_equal "revenue", ActionCandidate.last.department
  end

  test "should show action_candidate" do
    @action_candidate.action_candidate_score_snapshots.create!(
      business: @action_candidate.business,
      recorded_on: Date.current,
      raw_score: 10,
      judge_adjusted_score: 8,
      adjustment_multiplier: 0.8,
      raw_rank: 2,
      adjusted_rank: 3,
      rank_delta: -1,
      reason: "Judge補正で順位低下"
    )
    @action_candidate.action_execution_logs.create!(
      business: @action_candidate.business,
      planned_action: "SEO記事を1本作成",
      planned_quantity: 1,
      actual_action: "SEO記事作成 + LP改善",
      actual_quantity: 2,
      variance_reason: "LPの問題が見つかった",
      status: "changed"
    )
    @action_candidate.update_columns(
      metadata: @action_candidate.metadata.merge(
        "execution_feasibility_correction" => {
          "applied" => true,
          "feasibility_label" => "over_sized",
          "base_success_probability" => "0.6",
          "adjusted_success_probability" => "0.52",
          "reason" => "過去ログ上、同種提案は完了率が低いため数量を保守化"
        }
      )
    )

    get action_candidate_url(@action_candidate)
    assert_response :success
    assert_includes response.body, "提案と実行の差分"
    assert_includes response.body, "SEO記事作成 + LP改善"
    assert_includes response.body, "実行可能性補正"
    assert_includes response.body, "補正前 success_probability"
    assert_includes response.body, "over_sized"
    assert_includes response.body, "この候補に近い過去精度"
    assert_includes response.body, "このgeneration_source"
    assert_includes response.body, "信頼度ベース評価"
    assert_includes response.body, "最終期待値"
    assert_includes response.body, "GSC"
    assert_includes response.body, "Judge補正スコア履歴"
    assert_includes response.body, "Judge補正で順位低下"
    assert_includes response.body, "部門"
  end

  test "normal action candidate does not show direct executor button" do
    get action_candidate_url(@action_candidate)

    assert_response :success
    assert_not_includes response.body, "Executorへ送る"
  end

  test "data preparation action candidate shows direct executor button" do
    action_candidate = create_data_preparation_candidate

    get action_candidate_url(action_candidate)

    assert_response :success
    assert_includes response.body, "Executorへ送る"
  end

  test "sends data preparation action candidate to executor" do
    action_candidate = create_data_preparation_candidate

    assert_difference("AicooExecutorTask.count", 1) do
      post send_to_executor_action_candidate_url(action_candidate)
    end

    task = AicooExecutorTask.last
    assert_redirected_to admin_aicoo_executor_task_url(task)
    assert_equal "action_candidate", task.source_type
    assert_equal action_candidate.id, task.source_id
    assert_equal "data_preparation", task.execution_type
    assert_equal action_candidate.execution_prompt, task.execution_prompt
  end

  test "does not duplicate unfinished executor task" do
    action_candidate = create_data_preparation_candidate
    existing_task = AicooExecutor::TaskBuilder.from_action_candidate(action_candidate)

    assert_no_difference("AicooExecutorTask.count") do
      post send_to_executor_action_candidate_url(action_candidate)
    end

    assert_redirected_to admin_aicoo_executor_task_url(existing_task)
  end

  test "rejects direct executor send for normal action candidate" do
    assert_no_difference("AicooExecutorTask.count") do
      post send_to_executor_action_candidate_url(@action_candidate)
    end

    assert_redirected_to action_candidate_url(@action_candidate)
  end

  test "should get edit" do
    get edit_action_candidate_url(@action_candidate)
    assert_response :success
  end

  test "should update action_candidate" do
    patch action_candidate_url(@action_candidate), params: { action_candidate: writable_action_candidate_params.merge(title: "更新した行動候補") }
    assert_redirected_to action_candidate_url(@action_candidate)
  end

  test "should destroy action_candidate" do
    assert_difference("ActionCandidate.count", -1) do
      delete action_candidate_url(@action_candidate)
    end

    assert_redirected_to action_candidates_url
  end

  private

  def writable_action_candidate_params
    {
      action_type: @action_candidate.action_type,
      business_id: @action_candidate.business_id,
      confidence_score: @action_candidate.confidence_score,
      cost_yen: @action_candidate.cost_yen,
      description: @action_candidate.description,
      department: @action_candidate.department,
      evaluation_reason: @action_candidate.evaluation_reason,
      execution_prompt: @action_candidate.execution_prompt,
      expected_hours: @action_candidate.expected_hours,
      generation_source: @action_candidate.generation_source,
      immediate_value_yen: @action_candidate.immediate_value_yen,
      neglect_loss_90d_yen: 15_000,
      neglect_loss_reason: "記事更新を放置した場合の順位低下リスク",
      priority_score: @action_candidate.priority_score,
      risk_reduction_score: @action_candidate.risk_reduction_score,
      status: @action_candidate.status,
      strategic_value_score: @action_candidate.strategic_value_score,
      success_probability: @action_candidate.success_probability
    }
  end

  def create_data_preparation_candidate
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "吸えログの不足データを整備する",
      action_type: "data_preparation",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.6,
      expected_hours: 1,
      execution_prompt: "実行済みActionCandidateを3件選び、実行結果を記録してください。",
      metadata: {
        "metric_rule" => "correction_readiness",
        "missing_type" => [ "action_results" ],
        "required_count" => { "action_results" => 10 },
        "current_count" => { "action_results" => 0 },
        "business_id" => businesses(:suelog).id
      }
    )
  end
end

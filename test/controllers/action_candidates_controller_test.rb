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
    assert_includes response.body, "提案理由"
    assert_includes response.body, "Evidence Summary"
    assert_includes response.body, "Execution Guide"
    assert_includes response.body, "提案と実行の差分"
    assert_includes response.body, "Practicality"
    assert_includes response.body, "実行可能性"
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
    assert_includes response.body, "承認する"
    assert_includes response.body, "Developer Mode"
    assert_includes response.body, "実行指示書"
    assert_includes response.body, "現在"
    assert_includes response.body, "変更後"
    assert_includes response.body, "対象ページ"
    assert_includes response.body, "SERPとの差分"
    assert_includes response.body, "SERPとの差分"
    assert_includes response.body, "変更ファイルと完了条件"
    assert_includes response.body, "完了 / 実行結果を記録"
  end

  test "action workspace keeps today context and avoids business breadcrumb" do
    @action_candidate.update!(status: "idea")

    get action_workspace_url(@action_candidate)

    assert_response :success
    assert_includes response.body, "Todayから開いた1つの仕事です"
    assert_includes response.body, "Today"
    assert_includes response.body, "Action"
    assert_includes response.body, "戻る"
    assert_includes response.body, "実行する"
    assert_includes response.body, "保留"
    assert_includes response.body, "却下する"
    assert_includes response.body, "Businessを見る"
    assert_select ".aicoo-sidebar-child.active strong", text: "Today"
    assert_not_select ".aicoo-sidebar-child.active strong", text: "Businesses"
    assert_not_includes response.body, "この事業へ戻る"
  end

  test "show renders analyzer evidence in Japanese" do
    @action_candidate.update_columns(
      generation_source: "business_analyzer",
      metadata: @action_candidate.metadata.to_h.merge(
        "seo_action_type" => "improve_ctr_title",
        "execution_mode" => "content_creation",
        "execution_units" => [
          {
            "label" => "梅田 喫煙 居酒屋 のSEOタイトル/metaを1件改善",
            "query" => "梅田 喫煙 居酒屋",
            "target_amount" => 1,
            "estimated_minutes" => 20,
            "reason" => "高順位なのにCTRが低いため"
          }
        ],
        "evidence" => {
          "source" => [ "gsc", "ga4" ],
          "issue_type" => "seo_low_ctr_titles",
          "query" => "梅田 喫煙 居酒屋",
          "page_path" => "/umeda-smoking-izakaya",
          "current_value" => 0.005,
          "benchmark_value" => 0.03,
          "target_amount" => 5,
          "target_unit" => "件",
          "expected_effect" => "+120クリック/月",
          "reason" => "平均順位5位以内にもかかわらずCTRが0.5%です。"
        }
      )
    )

    get action_candidate_url(@action_candidate)

    assert_response :success
    assert_includes response.body, "Analyzer根拠"
    assert_includes response.body, "CTRタイトル改善"
    assert_includes response.body, "記事作成"
    assert_includes response.body, "今日やる単位"
    assert_includes response.body, "梅田 喫煙 居酒屋 のSEOタイトル/metaを1件改善"
    assert_includes response.body, "20分"
    assert_includes response.body, "GSC / GA4"
    assert_includes response.body, "「梅田 喫煙 居酒屋」 / /umeda-smoking-izakaya"
    assert_includes response.body, "0.5%"
    assert_includes response.body, "3.0%"
    assert_includes response.body, "5件"
    assert_includes response.body, "+120クリック/月"
    assert_not_includes response.body, "Codex用プロンプト生成"
  end

  test "does not generate codex prompt draft for non code revision candidate" do
    @action_candidate.update_columns(
      metadata: @action_candidate.metadata.to_h.merge("execution_mode" => "data_operation")
    )

    assert_no_difference("CodexPromptDraft.count") do
      post generate_codex_prompt_draft_action_candidate_url(@action_candidate)
    end

    assert_redirected_to action_candidate_url(@action_candidate)
    assert_includes flash[:alert], "Codex改修にはしません"
  end

  test "show links to existing codex prompt draft" do
    draft = CodexPromptDraft.from_action_candidate(@action_candidate)

    get action_candidate_url(@action_candidate)

    assert_response :success
    assert_includes response.body, "Codex用プロンプト確認"
    assert_includes response.body, owner_codex_prompt_draft_path(draft)
  end

  test "generates codex prompt draft" do
    assert_difference("CodexPromptDraft.count", 1) do
      post generate_codex_prompt_draft_action_candidate_url(@action_candidate)
    end

    draft = CodexPromptDraft.last
    assert_redirected_to owner_codex_prompt_draft_url(draft)
    assert_equal @action_candidate, draft.action_candidate
  end

  test "normal action candidate does not show direct executor button" do
    get action_candidate_url(@action_candidate)

    assert_response :success
    assert_not_includes response.body, "Executorへ送る"
  end

  test "data preparation action candidate hides direct executor button in CEO UI" do
    action_candidate = create_data_preparation_candidate

    get action_candidate_url(action_candidate)

    assert_response :success
    assert_not_includes response.body, "Executorへ送る"
    assert_includes response.body, "承認する"
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

  test "approves action candidate from quick action" do
    @action_candidate.update!(status: "idea")

    assert_difference("AutoRevisionTask.count", 1) do
      assert_difference("AicooExecutorTask.count", 1) do
        assert_difference("OwnerTaskCompletionLog.count", 1) do
          assert_difference("OwnerDecisionLog.count", 1) do
            assert_difference("ApprovalLog.count", 1) do
              assert_difference("ActionExecution.count", 1) do
                patch approve_action_candidate_url(@action_candidate), headers: { "HTTP_REFERER" => owner_tasks_url }
              end
            end
          end
        end
      end
    end

    auto_revision_task = AutoRevisionTask.last
    assert_redirected_to auto_revision_task_url(auto_revision_task)
    assert_equal "approved", @action_candidate.reload.status
    assert_equal "ready", @action_candidate.action_execution.status
    assert_equal "manual", @action_candidate.action_execution.execution_type
    assert_includes @action_candidate.action_execution.execution_prompt, @action_candidate.title
    assert_equal @action_candidate, auto_revision_task.action_candidate
    assert_equal "ready_for_codex", auto_revision_task.status
    assert_equal "approved", AicooExecutorTask.last.status
    assert_not_nil @action_candidate.approved_at
    assert_includes flash[:notice], "ActionCandidate『#{@action_candidate.title}』の改修を開始"
    assert_equal "改修開始", OwnerTaskCompletionLog.last.action_label
    assert_equal "approve", OwnerDecisionLog.last.decision_type
    assert_equal "action_candidate_detail", OwnerDecisionLog.last.decision_source
    assert_equal auto_revision_task.id, OwnerTaskCompletionLog.last.metadata["auto_revision_task_id"]
    assert_equal @action_candidate, ApprovalLog.last.approvable
    assert_equal "approve", ApprovalLog.last.action
    assert_equal "approved", ApprovalLog.last.common_new_status
  end

  test "approves from action workspace and returns to workspace" do
    @action_candidate.update!(status: "idea")

    patch approve_action_candidate_url(@action_candidate, return_to: action_workspace_path(@action_candidate))

    assert_redirected_to action_workspace_url(@action_candidate)
    assert_equal "approved", @action_candidate.reload.status
  end

  test "rejects from action workspace and returns to today" do
    @action_candidate.update!(status: "idea")

    patch reject_action_candidate_url(@action_candidate, return_to: owner_focus_path)

    assert_redirected_to owner_focus_url
    assert_equal "rejected", @action_candidate.reload.status
  end

  test "approving non code candidate does not create auto revision task" do
    @action_candidate.update!(
      status: "idea",
      title: "大阪エリアの掲載店舗を80件追加する"
    )
    @action_candidate.update_columns(
      metadata: @action_candidate.metadata.to_h.merge(
        "execution_mode" => "data_operation",
        "seo_action_type" => "add_listings"
      )
    )

    assert_no_difference("AutoRevisionTask.count") do
      assert_difference("AicooExecutorTask.count", 1) do
        patch approve_action_candidate_url(@action_candidate)
      end
    end

    assert_redirected_to action_candidate_url(@action_candidate)
    assert_equal "approved", @action_candidate.reload.status
    assert_includes flash[:notice], "Codex改修タスクは作成しません"
  end

  test "approving new business candidate creates visible business and reassigns candidate" do
    source_business = businesses(:suelog)
    candidate = ActionCandidate.create!(
      business: source_business,
      title: "フリーランス請求前チェックリスト",
      description: "請求前の抜け漏れを防ぐ新規サービス候補",
      action_type: "build_lp",
      department: "new_business",
      generation_source: "integrated_decision",
      status: "idea",
      immediate_value_yen: 80_000,
      success_probability: 0.3,
      expected_hours: 2,
      metadata: {
        "candidate_kind" => "new_business",
        "source_query" => "フリーランス 請求 チェックリスト",
        "problem" => "請求前の確認漏れ",
        "target_customer" => "個人で請求業務を行うフリーランス",
        "revenue_model" => "テンプレート販売またはSaaS"
      }
    )

    assert_difference("Business.real_businesses.count", 1) do
      assert_no_difference("AutoRevisionTask.count") do
        assert_difference("ApprovalLog.count", 1) do
          patch approve_action_candidate_url(candidate)
        end
      end
    end

    business = Business.real_businesses.find_by!(name: "フリーランス請求前チェックリスト")
    assert_redirected_to business_url(business)
    assert_equal business, candidate.reload.business
    assert_equal "approved", candidate.status
    assert_equal "integrated_decision", business.source
    assert_equal "lp_validation", business.lifecycle_stage
    assert_equal "launched", business.status
    assert business.created_by_aicoo?
    assert business.daily_run_enabled?
    assert business.serp_enabled?
    assert_equal "automatic", business.auto_revision_mode
    assert_equal "approval", business.auto_deploy_mode
    assert business.auto_build_enabled?
    assert_not business.auto_build_requires_approval?
    assert business.new_lp_auto_deploy_enabled?
    assert business.business_execution_profile.codex_enabled?
    assert business.business_execution_profile.codex_auto_submit_enabled?
    assert_includes business.metadata, "action_candidate_id"
    assert_includes flash[:notice], "Businessを作成しました: #{business.name}"

    get businesses_url
    assert_response :success
    assert_includes response.body, business.name
  end

  test "approving new business candidate links existing business without duplicate" do
    existing = Business.create!(
      name: "既存AIメモ事業",
      description: "既に存在する新規事業",
      status: "idea",
      lifecycle_stage: "lp_validation",
      resource_status: "active",
      business_type: "landing_page",
      source: "manual"
    )
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: existing.name,
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      status: "idea",
      immediate_value_yen: 50_000,
      success_probability: 0.2,
      metadata: { "candidate_kind" => "new_business" }
    )

    assert_no_difference("Business.count") do
      patch approve_action_candidate_url(candidate)
    end

    assert_redirected_to business_url(existing)
    assert_equal existing, candidate.reload.business
    assert_equal "approved", candidate.status
    assert_includes flash[:notice], "既存Businessに紐付けました: #{existing.name}"
  end

  test "rejects action candidate from quick action" do
    @action_candidate.update!(status: "idea")

    assert_difference("OwnerTaskCompletionLog.count", 1) do
      assert_difference("OwnerDecisionLog.count", 1) do
        assert_difference("ApprovalLog.count", 1) do
          patch reject_action_candidate_url(@action_candidate), headers: { "HTTP_REFERER" => owner_tasks_url }
        end
      end
    end

    assert_redirected_to owner_tasks_url
    assert_equal "rejected", @action_candidate.reload.status
    assert_includes flash[:notice], "ActionCandidate『#{@action_candidate.title}』を却下しました。"
    assert_equal "却下", OwnerTaskCompletionLog.last.action_label
    assert_equal "reject", OwnerDecisionLog.last.decision_type
    assert_equal "reject", ApprovalLog.last.action
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

require "test_helper"

class DepartmentRankingsControllerTest < ActionDispatch::IntegrationTest
  test "shows general ranking by default" do
    get department_rankings_url

    assert_response :success
    assert_includes response.body, "部門別ランキング"
    assert_includes response.body, "generalのみdepartment一括分類"
    assert_includes response.body, "全件再分類"
    assert_includes response.body, "評価式改善候補を生成"
    assert_includes response.body, "総合ランキング"
    assert_includes response.body, "Revenue"
    assert_includes response.body, "Lab"
    assert_includes response.body, "新規事業"
    assert_includes response.body, "部門別精度サマリー"
    assert_includes response.body, "実行済み件数"
    assert_includes response.body, "予測期待利益合計"
  end

  test "filters revenue department ranking" do
    revenue_action = action_candidates(:nagazakicho_article)
    revenue_action.update!(department: "revenue")
    lab_action = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Lab only ranking action",
      action_type: "data_preparation",
      department: "lab",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.4
    )

    get department_rankings_url(department: "revenue")

    assert_response :success
    assert_includes response.body, revenue_action.title
    assert_not_includes response.body, lab_action.title
    assert_includes response.body, "期待時給"
    assert_includes response.body, "ROI"
  end

  test "shows lab specific columns" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "LPテストで仮説検証を行う",
      action_type: "other",
      department: "lab",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.4,
      expected_learning_value_yen: 20_000,
      data_confidence_score: 80
    )

    get department_rankings_url(department: "lab")

    assert_response :success
    assert_includes response.body, action_candidate.title
    assert_includes response.body, "学習価値"
    assert_includes response.body, "データ信頼度"
    assert_includes response.body, "仮説検証"
  end

  test "shows new business specific columns" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "新規事業のMVP作成前に市場調査を行う",
      action_type: "other",
      department: "new_business",
      generation_source: "manual",
      immediate_value_yen: 30_000,
      success_probability: 0.5,
      metadata: { "market_size_score" => 90, "automation_rate_score" => 70, "launch_speed_score" => 80 }
    )

    get department_rankings_url(department: "new_business")

    assert_response :success
    assert_includes response.body, action_candidate.title
    assert_includes response.body, "市場規模"
    assert_includes response.body, "自動化率"
    assert_includes response.body, "初速"
    assert_includes response.body, "MVP"
  end

  test "classifies general departments from department rankings" do
    action_candidate = action_candidates(:nagazakicho_article)
    action_candidate.update!(department: "general", title: "GSC分析でCTR改善を行う")

    post classify_department_rankings_url

    assert_redirected_to department_rankings_url
    assert_match(/department一括分類を実行しました/, flash[:notice])
    assert_equal "revenue", action_candidate.reload.department
  end

  test "classifies all departments when requested" do
    action_candidate = action_candidates(:nagazakicho_article)
    action_candidate.update!(department: "revenue", title: "LPテストで仮説検証を行う")

    post classify_department_rankings_url(mode: "all")

    assert_redirected_to department_rankings_url
    assert_equal "lab", action_candidate.reload.department
  end

  test "generates evaluation tuning candidates from department rankings" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Revenue underperformance source",
      action_type: "other",
      department: "revenue",
      generation_source: "manual",
      immediate_value_yen: 100_000,
      success_probability: 1
    )
    ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: 8.days.ago.to_date,
      evaluated_on: Date.current,
      predicted_expected_profit_yen: 100_000,
      actual_profit_yen: 20_000,
      evaluation_status: "evaluated"
    )

    assert_difference("ActionCandidate.where(action_type: 'evaluation_tuning').count", 1) do
      post generate_evaluation_tuning_department_rankings_url
    end

    assert_redirected_to department_rankings_url
    assert_match(/評価式改善候補を1件生成しました/, flash[:notice])
  end
end

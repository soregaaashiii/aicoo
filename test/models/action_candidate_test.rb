require "test_helper"

class ActionCandidateTest < ActiveSupport::TestCase
  test "calculates expected profit hourly value roi and final score before save" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "吸えログで電話確認を外注する",
      action_type: "outsourcing",
      immediate_value_yen: 50_000,
      success_probability: 0.6,
      expected_hours: 2,
      cost_yen: 10_000,
      strategic_value_score: 50,
      risk_reduction_score: 30,
      confidence_score: 80,
      priority_score: 60,
      status: "pending"
    )

    assert_equal 30_000, action_candidate.expected_profit_yen
    assert_equal 15_000, action_candidate.expected_hourly_value_yen
    assert_equal 3.to_d, action_candidate.roi
    assert_equal 11_800.to_d, action_candidate.final_score
  end

  test "leaves hourly value and roi blank when denominators are blank or zero" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "新規事業候補のSERP調査をする",
      immediate_value_yen: 20_000,
      success_probability: 0.5,
      expected_hours: 0,
      cost_yen: 0
    )

    assert_equal 10_000, action_candidate.expected_profit_yen
    assert_nil action_candidate.expected_hourly_value_yen
    assert_nil action_candidate.roi
  end

  test "validates score ranges and success probability" do
    action_candidate = ActionCandidate.new(
      business: businesses(:suelog),
      title: "Invalid estimate",
      success_probability: 1.2,
      strategic_value_score: 101,
      risk_reduction_score: -1,
      confidence_score: 101,
      priority_score: -1
    )

    assert_not action_candidate.valid?
  end

  test "allows evaluation tuning action type" do
    action_candidate = ActionCandidate.new(
      business: businesses(:suelog),
      title: "Revenue評価式を見直す",
      action_type: "evaluation_tuning",
      success_probability: 0.5
    )

    assert action_candidate.valid?
  end

  test "auto classifies department when department is not specified" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "GSC分析でCTR改善を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "revenue", action_candidate.department
  end

  test "does not overwrite explicitly assigned department" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "GSC分析でCTR改善を行う",
      action_type: "other",
      department: "lab",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "lab", action_candidate.department
  end

  test "auto classifies seo ctr and gsc candidates as revenue" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SEO記事のCTRをGSCで改善する",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "revenue", action_candidate.department
  end

  test "auto classifies experiment validation and lp test candidates as lab" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "LPテストで仮説検証を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "lab", action_candidate.department
  end

  test "auto classifies new business mvp and market research candidates as new business" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "新規事業のMVP作成前に市場調査を行う",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "new_business", action_candidate.department
  end

  test "keeps unclear candidates as general" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "管理方針を整理する",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert_equal "general", action_candidate.department
  end
end

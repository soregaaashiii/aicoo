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
    assert_equal "11800.0", action_candidate.metadata.dig("strategic_learning", "base_score")
    assert action_candidate.final_score.positive?
    assert action_candidate.metadata.dig("strategic_learning", "strategic_score").present?
  end

  test "strategic philosophy changes final score" do
    setting = AicooSetting.current
    setting.update!(
      long_term_profit_weight: 45,
      short_term_profit_weight: 25,
      learning_weight: 15,
      automation_weight: 10,
      exploration_weight: 5
    )
    learning_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "学習データを増やす",
      action_type: "data_preparation",
      immediate_value_yen: 1_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    baseline_score = learning_candidate.final_score

    setting.update!(
      long_term_profit_weight: 0,
      short_term_profit_weight: 0,
      learning_weight: 100,
      automation_weight: 0,
      exploration_weight: 0
    )
    learning_candidate.update!(title: "学習データを増やす updated")

    assert_operator learning_candidate.reload.final_score, :>, baseline_score
  end

  test "zero strategic weights do not break scoring" do
    AicooSetting.current.update!(
      long_term_profit_weight: 0,
      short_term_profit_weight: 0,
      learning_weight: 0,
      automation_weight: 0,
      exploration_weight: 0
    )

    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Weight zero candidate",
      action_type: "other",
      immediate_value_yen: 10_000,
      success_probability: 0.5
    )

    assert action_candidate.final_score >= 0
    assert_equal "50.0", action_candidate.metadata.dig("strategic_learning", "strategic_score")
    assert action_candidate.metadata.dig("strategic_learning_guardrail", "base_score").present?
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

  test "applies execution feasibility correction before score calculation" do
    business = businesses(:suelog)
    seed_candidate = ActionCandidate.create!(
      business:,
      title: "SEO改善seed",
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    3.times do
      ActionExecutionLog.create!(
        action_candidate: seed_candidate,
        business:,
        planned_action: "500件実行",
        planned_quantity: 500,
        actual_action: "250件実行",
        actual_quantity: 250,
        status: "partial"
      )
    end

    action_candidate = ActionCandidate.create!(
      business:,
      title: "SEO改善候補",
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.6,
      expected_hours: 2,
      execution_prompt: "梅田店舗を500件追加してください。"
    )

    assert_equal 0.52.to_d, action_candidate.success_probability
    assert_equal 2.4.to_d, action_candidate.expected_hours
    assert_equal 5_200, action_candidate.expected_profit_yen
    assert_equal "over_sized", action_candidate.metadata.dig("execution_feasibility_correction", "feasibility_label")
  end

  test "applies prediction calibration to expected profit without overwriting raw probability" do
    ActionPredictionCalibration.create!(
      action_type: "serp_research",
      sample_count: 10,
      profit_calibration_factor: 0.5,
      probability_calibration_factor: 0.8
    )

    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SERP調査の補正テスト",
      action_type: "serp_research",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )

    assert_equal 2_500, action_candidate.expected_profit_yen
    assert_equal 0.5.to_d, action_candidate.success_probability
    assert_equal 0.4.to_d, action_candidate.calibrated_success_probability
    assert_equal true, action_candidate.metadata.dig("prediction_calibration", "active")
    assert_equal "0.5", action_candidate.metadata.dig("prediction_calibration", "profit_calibration_factor")
  end
end

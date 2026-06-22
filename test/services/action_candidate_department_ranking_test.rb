require "test_helper"

class ActionCandidateDepartmentRankingTest < ActiveSupport::TestCase
  test "returns general and department rankings without changing final score logic" do
    revenue_action = action_candidates(:nagazakicho_article)
    revenue_action.update!(department: "revenue", immediate_value_yen: 20_000, success_probability: 0.8)
    new_business_action = ActionCandidate.create!(
      business: businesses(:cards),
      title: "New business department action",
      action_type: "market_research",
      department: "new_business",
      generation_source: "manual",
      immediate_value_yen: 30_000,
      success_probability: 0.5
    )

    result = ActionCandidateDepartmentRanking.new(active_department: "revenue", limit: 10).call

    assert_includes result.rankings.map(&:action_candidate), revenue_action
    assert_not_includes result.rankings.map(&:action_candidate), new_business_action
    assert_equal "revenue", result.active_department
    assert_equal %w[general revenue lab new_business], result.tabs.map(&:key)
  end

  test "revenue ranking uses revenue department score" do
    low_revenue = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Low revenue score",
      action_type: "seo_improvement",
      department: "revenue",
      immediate_value_yen: 1_000,
      success_probability: 0.2,
      expected_hours: 10
    )
    high_revenue = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "High revenue score",
      action_type: "seo_improvement",
      department: "revenue",
      immediate_value_yen: 100_000,
      success_probability: 0.8,
      expected_hours: 1
    )

    result = ActionCandidateDepartmentRanking.new(active_department: "revenue", limit: 10).call

    assert_operator result.rankings.index { |row| row.action_candidate == high_revenue },
                    :<,
                    result.rankings.index { |row| row.action_candidate == low_revenue }
    assert_equal "revenue", result.rankings.first.department_score.department
    assert_includes result.rankings.first.summary_reason, "期待利益"
    assert_includes result.rankings.first.summary_reason, "期待時給"
  end

  test "lab ranking exposes learning metrics" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Lab score action",
      action_type: "data_preparation",
      department: "lab",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.4,
      data_confidence_score: 90
    )

    row = ActionCandidateDepartmentRanking.new(active_department: "lab", limit: 10).call.rankings.find { |ranking| ranking.action_candidate == action_candidate }

    assert_equal "lab", row.department_score.department
    assert_equal 90, row.department_score.data_confidence_score
    assert_includes row.summary_reason, "学習価値"
    assert_includes row.summary_reason, "低コスト"
  end

  test "new business ranking reads metadata scores" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:cards),
      title: "New business score action",
      action_type: "market_research",
      department: "new_business",
      generation_source: "manual",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      metadata: { "market_size_score" => 88, "automation_rate_score" => 77, "launch_speed_score" => 66 }
    )

    row = ActionCandidateDepartmentRanking.new(active_department: "new_business", limit: 10).call.rankings.find { |ranking| ranking.action_candidate == action_candidate }

    assert_equal 88, row.department_score.market_size_score
    assert_equal 77, row.department_score.automation_rate_score
    assert_equal 66, row.department_score.launch_speed_score
    assert_includes row.summary_reason, "市場規模 88"
    assert_includes row.summary_reason, "自動化率 77"
  end
end

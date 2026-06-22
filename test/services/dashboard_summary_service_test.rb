require "test_helper"

class DashboardSummaryServiceTest < ActiveSupport::TestCase
  test "summarizes latest daily run business metrics revenue and judge" do
    target_date = Date.current - 1
    AicooDailyRun.create!(
      started_at: Time.current,
      finished_at: Time.current,
      status: "succeeded",
      target_date:,
      action_candidates_generated_count: 3,
      action_results_evaluated_count: 2
    )
    business = businesses(:suelog)
    business.business_metric_dailies.create!(recorded_on: target_date - 1, clicks: 10)
    business.business_metric_dailies.create!(recorded_on: target_date, clicks: 15)
    business.revenue_events.create!(occurred_on: target_date, event_type: "revenue", amount: 12_000)
    business.revenue_events.create!(occurred_on: target_date, event_type: "expense", amount: 4_000)
    create_result(business:, generation_source: "ai_business", action_type: "seo_improvement", actual: 10_000)

    result = DashboardSummaryService.new.call

    assert_equal "succeeded", result.today.status
    assert_equal target_date, result.today.target_date
    assert_equal 3, result.today.action_candidates_generated_count
    assert_equal 2, result.today.action_results_evaluated_count
    assert_equal 12_000, result.today.revenue_total_yen
    assert_equal 8_000, result.today.profit_total_yen
    assert_operator result.today.proxy_score_change_rate, :>, 0
    assert_equal "ai_business", result.judge.top_generation_source.label
    assert_equal business.name, result.top_business.label
  end

  test "returns data shortage friendly summary when judge data is missing" do
    result = DashboardSummaryService.new.call

    assert_nil result.judge.top_generation_source
    assert_nil result.judge.summary.hit_rate
  end

  test "owner today tasks are backfilled to at least three when no candidates exist" do
    ActionCandidate.update_all(status: "archived")

    result = DashboardSummaryService.new.call

    assert_operator result.today_tasks.size, :>=, 3
    assert_operator result.owner_fallback_tasks.size, :>=, 3
    assert result.today_tasks.all? { |task| task.is_a?(ActionCandidate) }
  end

  test "owner today tasks are backfilled to at least three when only one candidate exists" do
    ActionCandidate.update_all(status: "archived")
    existing = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "既存の収益候補",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 10_000,
      success_probability: 0.7,
      expected_hours: 1
    )

    result = DashboardSummaryService.new.call

    assert_includes result.today_tasks, existing
    assert_operator result.today_tasks.size, :>=, 3
  end

  test "summarizes learning progress and aicoo maturity" do
    result = DashboardSummaryService.new.call

    assert_equal AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED, result.learning_progress.action_result_required
    assert_equal AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED, result.learning_progress.business_metric_required
    assert_operator result.aicoo_maturity_score, :>=, 0
    assert_operator result.aicoo_maturity_score, :<=, 100
    assert_includes [ "初期学習段階", "学習中", "Judge運用中", "自走運用中" ], result.aicoo_maturity_label
  end

  private

  def create_result(business:, generation_source:, action_type:, actual:)
    candidate = ActionCandidate.create!(
      business:,
      title: "Dashboard summary action #{SecureRandom.hex(4)}",
      action_type:,
      generation_source:,
      immediate_value_yen: 10_000,
      success_probability: 1,
      expected_hours: 1
    )
    ActionResult.create!(
      action_candidate: candidate,
      business:,
      executed_on: Date.current - 10,
      evaluated_on: Date.current,
      actual_profit_yen: actual,
      evaluation_status: "evaluated"
    )
  end
end

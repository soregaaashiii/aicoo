require "test_helper"

module AicooRevenue
  class PlanBuilderTest < ActiveSupport::TestCase
    test "selects rows within available minutes and budget" do
      rows = [
        row(title: "Plan first", expected_profit: 120_000, total_value: 60_000, minutes: 60, budget: 0, score: 50),
        row(title: "Plan second", expected_profit: 80_000, total_value: 40_000, minutes: 60, budget: 300, score: 40)
      ]

      plan = PlanBuilder.new(available_minutes: 120, available_budget_yen: 300, rows:).call

      assert_equal [ "Plan first", "Plan second" ], plan.selected_rows.map(&:title)
      assert_equal 120, plan.total_minutes
      assert_equal 300, plan.total_budget_yen
      assert_equal 100_000.to_d, plan.total_revenue_value_yen
      assert_equal 200_000, plan.total_expected_90d_profit_yen
      assert_equal 0, plan.total_neglect_loss_90d_yen
    end

    test "does not select rows that exceed remaining minutes" do
      rows = [
        row(title: "Plan selected by time", minutes: 90, budget: 0, score: 50),
        row(title: "Plan time overflow", minutes: 60, budget: 0, score: 40)
      ]

      plan = PlanBuilder.new(available_minutes: 120, available_budget_yen: 0, rows:).call

      assert_equal [ "Plan selected by time" ], plan.selected_rows.map(&:title)
      assert_equal 90, plan.total_minutes
    end

    test "does not select rows that exceed remaining budget" do
      rows = [
        row(title: "Plan selected by budget", minutes: 60, budget: 300, score: 50),
        row(title: "Plan budget overflow", minutes: 60, budget: 300, score: 40)
      ]

      plan = PlanBuilder.new(available_minutes: 180, available_budget_yen: 300, rows:).call

      assert_equal [ "Plan selected by budget" ], plan.selected_rows.map(&:title)
      assert_equal 300, plan.total_budget_yen
    end

    test "greedily selects by revenue score descending" do
      rows = [
        row(title: "Plan high score", minutes: 60, budget: 0, score: 50),
        row(title: "Plan low score", minutes: 60, budget: 0, score: 10)
      ]

      plan = PlanBuilder.new(available_minutes: 120, available_budget_yen: 0, rows:).call

      assert_equal [ "Plan high score", "Plan low score" ], plan.selected_rows.map(&:title)
    end

    private

    def row(title:, minutes:, budget:, score:, expected_profit: 50_000, total_value: 12_500, neglect_loss: 0)
      RankingBuilder::Row.new(
        title:,
        source: "candidate",
        source_id: 1,
        status: "proposed",
        experiment_type: "lp",
        market_category: "revenue market",
        expected_90d_profit_yen: expected_profit,
        success_probability: 0.25,
        manual_neglect_loss_90d_yen: neglect_loss,
        estimated_neglect_loss_90d_yen: 0,
        neglect_loss_auto_generated: false,
        neglect_loss_90d_yen: neglect_loss,
        neglect_loss_reason: nil,
        revenue_total_value_yen: total_value,
        estimated_work_minutes: minutes,
        budget_yen: budget,
        time_cost_yen: 0,
        revenue_score: score,
        expected_hourly_profit: score,
        roi_score: score,
        neglect_alert: false,
        neglected_days: 0,
        neglect_alert_reason: nil,
        url: "/admin/aicoo_lab/candidates/1"
      )
    end
  end
end

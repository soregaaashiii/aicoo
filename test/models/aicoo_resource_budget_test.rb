require "test_helper"

class AicooResourceBudgetTest < ActiveSupport::TestCase
  test "current creates safe default budget with auto build disabled" do
    AicooResourceBudget.delete_all

    budget = AicooResourceBudget.current

    assert_not budget.auto_build_enabled?
    assert_equal 1, budget.codex_concurrent_limit
    assert_equal 1, budget.simultaneous_mvp_limit
    assert budget.budget_available?(1_000)
  end

  test "resource availability checks budget and queue capacity" do
    budget = AicooResourceBudget.create!(
      auto_build_enabled: true,
      monthly_ai_budget_yen: 1_000,
      current_month_ai_spend_yen: 200,
      codex_concurrent_limit: 1,
      codex_waiting_limit: 5,
      build_queue_limit: 5,
      deploy_queue_limit: 5,
      render_service_limit: 0,
      simultaneous_mvp_limit: 5
    )

    assert budget.resource_available_for?(800)
    assert_not budget.resource_available_for?(801)
  end
end

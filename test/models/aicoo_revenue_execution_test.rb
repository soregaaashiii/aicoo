require "test_helper"

class AicooRevenueExecutionTest < ActiveSupport::TestCase
  test "calculates error rate and calibration score when actual profit is saved" do
    execution = create_execution(revenue_total_value_yen: 40_000)

    execution.update!(actual_90d_profit_yen: 30_000)

    assert_equal 0.25.to_d, execution.error_rate
    assert_equal 75.to_d, execution.calibration_score
    assert_not_nil execution.measured_at
  end

  test "calibration score is floored at zero" do
    execution = create_execution(revenue_total_value_yen: 10_000)

    execution.update!(actual_90d_profit_yen: 30_000)

    assert_equal 2.to_d, execution.error_rate
    assert_equal 0.to_d, execution.calibration_score
  end

  test "does not divide by zero when predicted value is zero" do
    execution = create_execution(revenue_total_value_yen: 0)

    execution.update!(actual_90d_profit_yen: 10_000)

    assert_nil execution.error_rate
    assert_nil execution.calibration_score
    assert_not_nil execution.measured_at
  end

  private

  def create_execution(attributes = {})
    AicooRevenueExecution.create!(
      {
        source_type: "candidate",
        source_id: 1,
        title: "Revenue execution result",
        expected_90d_profit_yen: 50_000,
        success_probability: 0.25,
        revenue_total_value_yen: 12_500,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "done"
      }.merge(attributes)
    )
  end
end

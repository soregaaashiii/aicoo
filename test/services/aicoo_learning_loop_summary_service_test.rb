require "test_helper"

class AicooLearningLoopSummaryServiceTest < ActiveSupport::TestCase
  setup do
    ActionExecutionLog.delete_all
    ActionResult.delete_all
    RevenueEvent.delete_all
    @business = businesses(:suelog)
  end

  test "returns not started without execution logs" do
    create_candidate

    summary = service_summary

    assert_equal "not_started", summary.learning_state_label
    assert_equal "実行ログをもっと登録してください。", summary.next_missing_item
  end

  test "returns collecting execution data with execution logs but few results" do
    candidate = create_candidate
    create_execution_log(candidate)

    summary = service_summary

    assert_equal "collecting_execution_data", summary.learning_state_label
    assert_equal 1, summary.total_execution_logs
    assert_equal 1.to_d, summary.execution_log_coverage_rate
  end

  test "returns collecting result data when action results exist but no correction" do
    3.times do
      candidate = create_candidate
      create_execution_log(candidate)
      create_action_result(candidate)
    end

    summary = service_summary

    assert_equal "collecting_result_data", summary.learning_state_label
    assert_equal 3, summary.candidates_with_action_results
  end

  test "returns correction active when corrections exist" do
    3.times do
      candidate = create_candidate
      create_execution_log(candidate)
      create_action_result(candidate)
      mark_corrected(candidate)
    end

    summary = service_summary

    assert_equal "correction_active", summary.learning_state_label
    assert_equal 3, summary.corrected_candidates_count
    assert_equal 1.to_d, summary.correction_rate
  end

  test "returns learning loop active with enough logs results corrections and revenue" do
    5.times do
      candidate = create_candidate
      2.times { create_execution_log(candidate) }
      create_action_result(candidate)
      candidate.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 1_000)
      mark_corrected(candidate)
    end

    summary = service_summary

    assert_equal "learning_loop_active", summary.learning_state_label
    assert_equal 10, summary.total_execution_logs
    assert_equal 5, summary.candidates_with_action_results
    assert_equal 5, summary.candidates_with_revenue_events
  end

  test "does not break with empty metadata" do
    create_candidate.update_columns(metadata: {})

    summary = service_summary

    assert_equal 1, summary.total_candidates
    assert_equal 0, summary.corrected_candidates_count
  end

  private

  def service_summary
    candidate_ids = ActionCandidate.where("title LIKE ?", "Learning Loop%").pluck(:id)
    AicooLearningLoopSummaryService.new(
      candidate_scope: ActionCandidate.where(id: candidate_ids),
      execution_log_scope: ActionExecutionLog.where(action_candidate_id: candidate_ids),
      action_result_scope: ActionResult.where(action_candidate_id: candidate_ids),
      revenue_event_scope: RevenueEvent.where(business: @business)
    ).call
  end

  def create_candidate
    ActionCandidate.create!(
      business: @business,
      title: "Learning Loop #{SecureRandom.hex(4)}",
      action_type: "seo_improvement",
      immediate_value_yen: 1_000,
      success_probability: 0.5,
      expected_hours: 1
    )
  end

  def create_execution_log(candidate)
    ActionExecutionLog.create!(
      action_candidate: candidate,
      business: candidate.business,
      planned_action: "10件実行",
      planned_quantity: 10,
      actual_action: "8件実行",
      actual_quantity: 8,
      status: "partial"
    )
  end

  def create_action_result(candidate)
    ActionResult.create!(
      action_candidate: candidate,
      business: candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current,
      actual_profit_yen: 500,
      evaluation_status: "evaluated"
    )
  end

  def mark_corrected(candidate)
    candidate.update_columns(
      metadata: {
        "execution_feasibility_correction" => {
          "applied" => true,
          "feasibility_label" => "over_sized",
          "base_success_probability" => "0.60",
          "adjusted_success_probability" => "0.52",
          "base_expected_hours" => "1.0",
          "adjusted_expected_hours" => "1.2",
          "reason" => "過大提案補正"
        }
      }
    )
  end
end

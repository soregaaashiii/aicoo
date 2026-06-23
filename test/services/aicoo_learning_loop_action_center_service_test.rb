require "test_helper"

class AicooLearningLoopActionCenterServiceTest < ActiveSupport::TestCase
  setup do
    ActionExecutionLog.delete_all
    ActionResult.delete_all
    RevenueEvent.delete_all
    @business = businesses(:suelog)
  end

  test "extracts candidates missing execution logs" do
    candidate = create_candidate("Missing execution log")

    summary = service_summary

    assert_equal 1, summary.execution_log_backlog_count
    assert_equal candidate, summary.candidates_missing_execution_logs.first.action_candidate
    assert_equal "実行差分を記録", summary.candidates_missing_execution_logs.first.quick_action_label
  end

  test "extracts candidates missing action results" do
    candidate = create_candidate("Missing action result")
    create_execution_log(candidate)

    summary = service_summary

    assert_equal 0, summary.execution_log_backlog_count
    assert_equal 1, summary.action_result_backlog_count
    assert_equal candidate, summary.candidates_missing_action_results.first.action_candidate
    assert_equal "結果を登録", summary.candidates_missing_action_results.first.quick_action_label
  end

  test "extracts candidates missing revenue events" do
    candidate = create_candidate("Missing revenue event")
    create_execution_log(candidate)
    create_action_result(candidate)

    summary = service_summary

    assert_equal 0, summary.action_result_backlog_count
    assert_equal 1, summary.revenue_event_backlog_count
    assert_equal candidate, summary.candidates_missing_revenue_events.first.action_candidate
    assert_equal "売上を登録", summary.candidates_missing_revenue_events.first.quick_action_label
  end

  test "does not report revenue backlog when action candidate has revenue events" do
    candidate = create_candidate("Revenue event exists")
    create_execution_log(candidate)
    create_action_result(candidate)
    candidate.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 1_000)

    summary = service_summary

    assert_equal 0, summary.revenue_event_backlog_count
    assert_empty summary.candidates_missing_revenue_events
  end

  test "does not report revenue backlog when action result has revenue events" do
    candidate = create_candidate("Result revenue event exists")
    create_execution_log(candidate)
    result = create_action_result(candidate)
    result.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 1_000)

    summary = service_summary

    assert_equal 0, summary.revenue_event_backlog_count
    assert_empty summary.candidates_missing_revenue_events
  end

  test "does not report revenue backlog when execution log has revenue events" do
    candidate = create_candidate("Log revenue event exists")
    log = create_execution_log(candidate)
    create_action_result(candidate)
    log.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 1_000)

    summary = service_summary

    assert_equal 0, summary.revenue_event_backlog_count
    assert_empty summary.candidates_missing_revenue_events
  end

  test "excludes auto linked candidates from action result backlog" do
    candidate = create_candidate("Auto linked result")
    log = create_execution_log(candidate)
    result = create_action_result(candidate)
    log.update!(
      action_result: result,
      metadata: {
        "auto_linked_action_result_id" => result.id,
        "auto_linked_at" => Time.current.iso8601,
        "auto_link_method" => "nearest_action_execution_log"
      }
    )

    summary = service_summary

    assert_equal 0, summary.action_result_backlog_count
    assert_empty summary.candidates_missing_action_results
  end

  test "excludes archived and rejected candidates" do
    create_candidate("Archived candidate", status: "archived")
    create_candidate("Rejected candidate", status: "rejected")

    summary = service_summary

    assert_equal 0, summary.execution_log_backlog_count
    assert summary.empty?
  end

  test "orders backlog by final score expected value and created_at" do
    low = create_candidate("Low priority", final_score: 10, immediate_value_yen: 10_000)
    high = create_candidate("High priority", final_score: 100, immediate_value_yen: 1_000)

    summary = service_summary

    assert_equal high, summary.candidates_missing_execution_logs.first.action_candidate
    assert_includes summary.candidates_missing_execution_logs.map(&:action_candidate), low
  end

  test "does not break with no candidates" do
    summary = AicooLearningLoopActionCenterService.new(candidate_scope: ActionCandidate.none).call

    assert summary.empty?
    assert_empty summary.candidates_missing_execution_logs
    assert_empty summary.candidates_missing_action_results
    assert_empty summary.candidates_missing_revenue_events
  end

  private

  def service_summary
    candidate_ids = ActionCandidate.where("title LIKE ?", "%Action Center%").pluck(:id)
    AicooLearningLoopActionCenterService.new(candidate_scope: ActionCandidate.where(id: candidate_ids)).call
  end

  def create_candidate(title, status: "idea", final_score: 10, immediate_value_yen: 1_000)
    candidate = ActionCandidate.create!(
      business: @business,
      title: "Action Center #{title}",
      action_type: "seo_improvement",
      status:,
      immediate_value_yen:,
      success_probability: 0.5,
      expected_hours: 1
    )
    candidate.update_columns(final_score:)
    candidate
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
end

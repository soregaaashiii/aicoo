require "test_helper"

class AicooExecutionFeasibilityInsightServiceTest < ActiveSupport::TestCase
  setup do
    ActionExecutionLog.delete_all
    @action_candidate = action_candidates(:nagazakicho_article)
  end

  test "returns insufficient data when logs are few" do
    create_log(status: "completed", planned: 10, actual: 10)

    summary = AicooExecutionFeasibilityInsightService.new.call.fetch(:overall)

    assert_equal "insufficient_data", summary.feasibility_label
    assert_equal 1, summary.total_logs
  end

  test "returns easy to execute when completed logs are strong" do
    3.times { create_log(status: "completed", planned: 10, actual: 10) }

    summary = AicooExecutionFeasibilityInsightService.new.call.fetch(:overall)

    assert_equal "easy_to_execute", summary.feasibility_label
    assert_equal 100, summary.completion_rate_score
    assert_equal 3, summary.completed_count
  end

  test "returns over sized when partial logs are common" do
    3.times { create_log(status: "partial", planned: 10, actual: 4) }

    summary = AicooExecutionFeasibilityInsightService.new.call.fetch(:overall)

    assert_equal "over_sized", summary.feasibility_label
    assert_operator summary.average_completion_rate, :<, 0.6
  end

  test "returns unstable when changed logs are common" do
    3.times { create_log(status: "changed", planned: 10, actual: 9) }

    summary = AicooExecutionFeasibilityInsightService.new.call.fetch(:overall)

    assert_equal "unstable", summary.feasibility_label
    assert_equal 3, summary.changed_count
  end

  test "returns hard to execute when failed and skipped logs are common" do
    create_log(status: "failed", planned: 10, actual: 0)
    create_log(status: "skipped", planned: 10, actual: 0)
    create_log(status: "completed", planned: 10, actual: 10)

    summary = AicooExecutionFeasibilityInsightService.new.call.fetch(:overall)

    assert_equal "hard_to_execute", summary.feasibility_label
    assert_equal 1, summary.failed_count
    assert_equal 1, summary.skipped_count
  end

  test "groups summaries by action type and business" do
    3.times { create_log(status: "completed", planned: 10, actual: 10) }

    result = AicooExecutionFeasibilityInsightService.new.call

    assert_equal @action_candidate.action_type, result.fetch(:by_action_type).first.label
    assert_equal @action_candidate.business.name, result.fetch(:by_business).first.label
  end

  private

  def create_log(status:, planned:, actual:)
    ActionExecutionLog.create!(
      action_candidate: @action_candidate,
      business: @action_candidate.business,
      planned_action: "提案を#{planned}件実行",
      planned_quantity: planned,
      actual_action: "実際に#{actual}件実行",
      actual_quantity: actual,
      status:
    )
  end
end

require "test_helper"

class AicooLearningLoopAutoLinkServiceTest < ActiveSupport::TestCase
  setup do
    ActionExecutionLog.delete_all
    ActionResult.delete_all
    @action_candidate = action_candidates(:nagazakicho_article)
  end

  test "links action result to an unlinked action execution log with same action candidate" do
    result = create_result(@action_candidate)
    log = create_log(@action_candidate, finished_at: Time.current)

    linked = AicooLearningLoopAutoLinkService.new(result).call

    assert_equal log, linked
    assert_equal result, log.reload.action_result
    assert_equal result.id, log.metadata["auto_linked_action_result_id"]
    assert_equal "nearest_action_execution_log", log.metadata["auto_link_method"]
    assert log.metadata["auto_linked_at"].present?
  end

  test "does not link logs from a different action candidate" do
    other_candidate = action_candidates(:ui_improvement)
    result = create_result(@action_candidate)
    log = create_log(other_candidate)

    linked = AicooLearningLoopAutoLinkService.new(result).call

    assert_nil linked
    assert_nil log.reload.action_result
  end

  test "does not overwrite an already linked execution log" do
    existing_result = create_result(@action_candidate)
    log = create_log(@action_candidate, action_result: existing_result)

    linked = AicooLearningLoopAutoLinkService.new(existing_result).call

    assert_nil linked
    assert_equal existing_result, log.reload.action_result
  end

  test "does not link when multiple candidates are ambiguous" do
    timestamp = Time.current
    result = create_result(@action_candidate)
    first_log = create_log(@action_candidate, finished_at: timestamp)
    second_log = create_log(@action_candidate, finished_at: timestamp)

    linked = AicooLearningLoopAutoLinkService.new(result).call

    assert_nil linked
    assert_nil first_log.reload.action_result
    assert_nil second_log.reload.action_result
  end

  test "links the nearest execution log when multiple candidates are not ambiguous" do
    result = create_result(@action_candidate, executed_on: Date.current)
    far_log = create_log(@action_candidate, finished_at: 3.days.ago)
    near_log = create_log(@action_candidate, finished_at: Time.zone.today.noon)

    linked = AicooLearningLoopAutoLinkService.new(result).call

    assert_equal near_log, linked
    assert_equal result, near_log.reload.action_result
    assert_nil far_log.reload.action_result
  end

  private

  def create_log(action_candidate, action_result: nil, finished_at: Time.current)
    ActionExecutionLog.create!(
      action_candidate:,
      business: action_candidate.business,
      action_result:,
      planned_action: "梅田店舗を500件追加",
      planned_quantity: 500,
      actual_action: "梅田店舗を400件追加",
      actual_quantity: 400,
      status: "partial",
      finished_at:
    )
  end

  def create_result(action_candidate, executed_on: Date.current)
    ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on:,
      evaluated_on: Date.current,
      actual_profit_yen: 1_000
    )
  end
end

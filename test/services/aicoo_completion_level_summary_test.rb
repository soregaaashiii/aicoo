require "test_helper"

class AicooCompletionLevelSummaryTest < ActiveSupport::TestCase
  test "returns seven completion levels in order" do
    levels = AicooCompletionLevelSummary.new.levels

    assert_equal 7, levels.size
    assert_equal [ 1, 2, 3, 4, 5, 6, 7 ], levels.map(&:level)
    assert_equal %w[
      事業管理
      データ分析
      行動提案
      結果評価
      評価式改善
      自動実行
      自動ピボット
    ], levels.map(&:title)
  end

  test "level status helpers return Japanese labels" do
    complete = build_level(status: "complete")
    partial = build_level(status: "partial")
    pending = build_level(status: "pending")

    assert complete.complete?
    assert partial.partial?
    assert pending.pending?
    assert_equal "完了", complete.status_label
    assert_equal "一部完了", partial.status_label
    assert_equal "未着手", pending.status_label
  end

  test "each level returns next action guidance" do
    levels = AicooCompletionLevelSummary.new.levels

    levels.first(6).each do |level|
      assert level.next_action.label.present?
      assert level.next_action.path.present?
      assert level.next_action.reason.present?
      assert level.next_action.available?
      assert level.missing_item.present?
    end

    auto_pivot = levels.last
    assert_equal "自動ピボット", auto_pivot.title
    assert_equal "将来実装", auto_pivot.next_action.label
    assert_nil auto_pivot.next_action.path
    assert_not auto_pivot.next_action.available?
  end

  test "evaluation tuning level reflects evaluated results and tuning candidates" do
    ActionCandidate.where(action_type: "evaluation_tuning").delete_all
    ActionResult.delete_all

    pending_level = find_level("評価式改善")
    assert_equal "pending", pending_level.status

    create_action_result(evaluation_status: "evaluated")
    partial_level = find_level("評価式改善")
    assert_equal "partial", partial_level.status

    create_action_candidate(action_type: "evaluation_tuning")
    complete_level = find_level("評価式改善")
    assert_equal "complete", complete_level.status
  end

  private

  def build_level(status:)
    AicooCompletionLevelSummary::Level.new(
      level: 1,
      title: "テスト",
      status:,
      description: "テスト",
      missing_item: "テスト不足",
      current_count: 0,
      required_count: 1,
      next_action: AicooCompletionLevelSummary::NextAction.new(label: "次へ", path: "/dashboard", reason: "理由")
    )
  end

  def find_level(title)
    AicooCompletionLevelSummary.new.levels.find { |level| level.title == title }
  end

  def create_action_candidate(action_type: "seo_improvement")
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "#{action_type} completion test",
      action_type:,
      generation_source: "manual",
      immediate_value_yen: 10_000,
      expected_profit_yen: 5_000,
      success_probability: 0.5,
      expected_hours: 1,
      confidence_score: 50
    )
  end

  def create_action_result(evaluation_status:)
    action_candidate = create_action_candidate

    ActionResult.create!(
      action_candidate:,
      business: action_candidate.business,
      executed_on: 8.days.ago.to_date,
      evaluated_on: Date.current,
      predicted_expected_profit_yen: 5_000,
      actual_profit_yen: 4_000,
      evaluation_status:
    )
  end
end

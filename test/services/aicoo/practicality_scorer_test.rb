require "test_helper"

module Aicoo
  class PracticalityScorerTest < ActiveSupport::TestCase
    test "scores concrete candidate high" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "CTR2%未満の記事5本をタイトル改訂する",
        action_type: "seo_improvement",
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本を選び、タイトルを改訂して公開してください。完了条件: 5本公開。",
        metadata: {
          "evidence" => {
            "score" => "75",
            "warning" => false
          }
        }
      )

      result = PracticalityScorer.new(candidate).call

      assert_operator result.practicality_score, :>=, 70
      assert_not result.practicality_warning
      assert_operator result.subscores.fetch(:target_clarity_score), :>=, 45
      assert_operator result.subscores.fetch(:deliverable_score), :>=, 45
    end

    test "penalizes missing evidence" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "CTR2%未満の記事5本をタイトル改訂する",
        action_type: "seo_improvement",
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本を選び、タイトルを改訂して公開してください。完了条件: 5本公開。"
      )

      result = PracticalityScorer.new(candidate).call

      assert_includes result.missing_items, "根拠データが不足しています"
    end

    test "scores abstract candidate low" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "アクセスが増えているページを改善する",
        action_type: "other",
        execution_prompt: "アクセスが増えているページを最適化してください。"
      )

      result = PracticalityScorer.new(candidate).call

      assert_operator result.practicality_score, :<, 30
      assert result.practicality_warning
      assert_includes result.missing_items, "対象が特定されていません"
    end
  end
end

require "test_helper"

module Aicoo
  class PracticalitySummaryTest < ActiveSupport::TestCase
    test "summarizes practicality scores and decision rates" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "CTR2%未満の記事5本をタイトル改訂する",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 0.5,
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本を選び、タイトルを改訂して公開してください。完了条件: 5本公開。"
      )
      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )

      summary = PracticalitySummary.new.call

      assert_operator summary.average_practicality_score, :>, 0
      assert_equal 0, summary.low_practicality_count
      assert_includes summary.top_candidates, candidate
      assert summary.adoption_rates.any? { |rate| rate.bucket == "high" && rate.positive_count.positive? }
    end
  end
end

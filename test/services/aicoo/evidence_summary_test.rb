require "test_helper"

module Aicoo
  class EvidenceSummaryTest < ActiveSupport::TestCase
    test "summarizes evidence attachment and decision rates" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "CTR2%未満の記事5本をタイトル改訂する",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 0.5,
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本を選び、タイトルを改訂して公開してください。完了条件: 5本公開。",
        metadata: {
          "evaluator_breakdown" => [
            {
              "evaluator_type" => "gsc",
              "expected_value_yen" => 10_000,
              "confidence_score" => 90,
              "reason" => "表示回数が増えています。"
            }
          ]
        }
      )
      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )

      summary = EvidenceSummary.new.call

      assert_operator summary.evidence_attached_count, :>=, 1
      assert_operator summary.average_evidence_score, :>, 0
      assert summary.adoption_rates.any? { |rate| rate.positive_count.positive? }
    end
  end
end

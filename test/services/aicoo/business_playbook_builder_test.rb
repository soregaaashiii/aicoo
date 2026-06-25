require "test_helper"

module Aicoo
  class BusinessPlaybookBuilderTest < ActiveSupport::TestCase
    test "creates business playbook with action type summary" do
      business = businesses(:suelog)
      candidate = ActionCandidate.create!(
        business:,
        title: "Playbook SEO candidate",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本をタイトル改訂してください。"
      )
      ActionResult.create!(
        action_candidate: candidate,
        business:,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_profit_yen: 8_000
      )
      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )

      playbook = BusinessPlaybookBuilder.new(business).update!

      assert_predicate playbook, :persisted?
      assert_equal business, playbook.business
      assert_operator playbook.sample_count, :>, 0
      assert_operator playbook.confidence_score, :>, 0
      assert_equal "seo_improvement", playbook.top_action_type
      assert playbook.action_type_summary.key?("seo_improvement")
    end

    test "updates all businesses" do
      result = BusinessPlaybookBuilder.update_all!

      assert_equal Business.count, result.updated_count
      assert_equal Business.count, BusinessPlaybook.count
    end
  end
end

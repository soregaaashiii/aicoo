require "test_helper"

module Aicoo
  class ApprovalKpiSummaryTest < ActiveSupport::TestCase
    test "counts only reasoned owner approvals and reports reasonless approvals" do
      candidate = action_candidates(:nagazakicho_article)
      reasoned = AutoRevisionTask.create!(
        business: candidate.business,
        action_candidate: candidate,
        title: "予算を使う改修",
        execution_prompt: "広告費を使う導線を追加する",
        status: "waiting_approval",
        risk_level: "medium",
        priority_score: 100,
        metadata: { "approval_required_reason" => "新しいお金を使うためOwner判断が必要です。" }
      )
      reasonless = AutoRevisionTask.create!(
        business: candidate.business,
        action_candidate: candidate,
        title: "理由なし文言改修",
        execution_prompt: "表示文言を変更する",
        status: "waiting_approval",
        risk_level: "low",
        priority_score: 100
      )

      summary = ApprovalKpiSummary.new.call

      assert_equal "waiting_approval", reasoned.reload.status
      assert_equal "ready_for_codex", reasonless.reload.status
      assert_operator summary.pending_approval_count, :>=, 1
      assert_equal 0, summary.reasonless_approval_count
      assert_equal 0, summary.ideal_reasonless_approval_count
      assert_equal "0〜3件", summary.ideal_pending_approval_range
      assert_equal "95%以上", summary.ideal_auto_execution_rate
    end
  end
end

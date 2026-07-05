require "test_helper"

module Aicoo
  module Owner
    class AutoRevisionLoopBoardTest < ActiveSupport::TestCase
      setup do
        Business.update_all(auto_revision_mode: "manual")
      end

      test "returns codex queue state for reasonless waiting task" do
        task = AutoRevisionTask.create!(
          action_candidate: action_candidates(:nagazakicho_article),
          business: businesses(:suelog),
          title: "待機中の改修",
          execution_prompt: "SEO titleを改善する",
          status: "waiting_approval",
          risk_level: "low",
          priority_score: 100
        )

        result = AutoRevisionLoopBoard.new(selected_key: "auto_revision_task:#{task.id}").call

        assert_equal "Codex送信待ち", result.selected.current_state
        assert_equal 40, result.selected.progress_percent
        assert_equal "Codex用プロンプト未コピー", result.selected.stuck_reason
        assert_equal "GitHub Issueを作成", result.selected.next_action_label
        assert_match %r{/owner/auto_revision_loop/auto_revision_tasks/#{task.id}/create_github_issue}, result.selected.next_action_path
      end

      test "returns owner decision state only when reason is present" do
        task = AutoRevisionTask.create!(
          action_candidate: action_candidates(:nagazakicho_article),
          business: businesses(:suelog),
          title: "広告費の予算を増やす",
          execution_prompt: "広告費の予算を増やす",
          status: "waiting_approval",
          risk_level: "medium",
          priority_score: 100,
          metadata: { "approval_required_reason" => "新しいお金を使うためOwner判断が必要です。" }
        )

        result = AutoRevisionLoopBoard.new(selected_key: "auto_revision_task:#{task.id}").call

        assert_equal "Owner判断待ち", result.selected.current_state
        assert_equal 15, result.selected.progress_percent
        assert_equal "新しいお金を使うためOwner判断が必要です。", result.selected.stuck_reason
        assert_equal "判断する", result.selected.next_action_label
      end
    end
  end
end

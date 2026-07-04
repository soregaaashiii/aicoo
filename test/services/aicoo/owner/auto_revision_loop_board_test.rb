require "test_helper"

module Aicoo
  module Owner
    class AutoRevisionLoopBoardTest < ActiveSupport::TestCase
      test "returns current state and next action for waiting approval task" do
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

        assert_equal "承認待ち", result.selected.current_state
        assert_equal 20, result.selected.progress_percent
        assert_equal "Owner承認待ち", result.selected.stuck_reason
        assert_equal "承認する", result.selected.next_action_label
        assert_match %r{/owner/auto_revision_loop/auto_revision_tasks/#{task.id}/approve}, result.selected.next_action_path
      end
    end
  end
end

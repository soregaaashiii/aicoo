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

      test "orders common revision candidates by final expected yen" do
        low_candidate = action_candidates(:nagazakicho_article)
        high_candidate = action_candidates(:ui_improvement)
        low_candidate.update_columns(status: "approved", final_expected_value_yen: 20_000, final_score: 99_999)
        high_candidate.update_columns(status: "approved", final_expected_value_yen: 80_000, final_score: 1)
        low_task = create_task!(low_candidate, priority_score: 99_999)
        high_task = create_task!(high_candidate, priority_score: 1)

        rows = AutoRevisionLoopBoard.new(limit: 100).call.rows
        common_ids = rows.filter_map(&:auto_revision_task).map(&:id) & [ low_task.id, high_task.id ]

        assert_equal [ high_task.id, low_task.id ], common_ids
        assert_equal [ 80_000, 20_000 ], rows.select { |row| common_ids.include?(row.auto_revision_task&.id) }.map(&:expected_profit_yen)
      end

      private

      def create_task!(candidate, priority_score:)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business: candidate.business,
          title: candidate.title,
          execution_prompt: candidate.execution_prompt,
          status: "waiting_approval",
          risk_level: "low",
          priority_score:
        )
      end
    end
  end
end

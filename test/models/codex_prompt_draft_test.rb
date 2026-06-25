require "test_helper"

class CodexPromptDraftTest < ActiveSupport::TestCase
  test "creates draft from action candidate once" do
    candidate = action_candidates(:nagazakicho_article)

    assert_difference("CodexPromptDraft.count", 1) do
      draft = CodexPromptDraft.from_action_candidate(candidate)

      assert_equal candidate, draft.action_candidate
      assert_equal candidate.business, draft.business
      assert_equal "draft", draft.status
      assert_includes draft.prompt_body, "目的:"
      assert_includes draft.prompt_body, "db:drop / db:reset / drop database"
      assert_includes draft.verification_commands, "bin/rails test"
    end

    assert_no_difference("CodexPromptDraft.count") do
      assert_equal CodexPromptDraft.last, CodexPromptDraft.from_action_candidate(candidate)
    end
  end

  test "status transitions" do
    draft = CodexPromptDraft.from_action_candidate(action_candidates(:nagazakicho_article))

    draft.approve!
    assert_equal "approved", draft.status

    draft.mark_copied!
    assert_equal "copied", draft.status
    assert draft.metadata["copied_at"].present?

    draft.mark_executed!
    assert_equal "executed", draft.status
    assert draft.metadata["executed_at"].present?

    draft.reject!
    assert_equal "rejected", draft.status
  end
end

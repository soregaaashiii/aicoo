require "test_helper"

module Owner
  class CodexPromptDraftsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @draft = CodexPromptDraft.from_action_candidate(action_candidates(:nagazakicho_article))
    end

    test "shows draft index" do
      get owner_codex_prompt_drafts_url

      assert_response :success
      assert_includes response.body, "Codex Prompt Drafts"
      assert_includes response.body, @draft.title
      assert_includes response.body, @draft.status
    end

    test "filters by status" do
      @draft.update!(status: "approved")
      rejected = CodexPromptDraft.create!(
        action_candidate: action_candidates(:ui_improvement),
        business: businesses(:cards),
        title: "Rejected draft",
        prompt_body: "body",
        risk_level: "low",
        status: "rejected",
        verification_commands: CodexPromptDraft::DEFAULT_VERIFICATION_COMMANDS
      )

      get owner_codex_prompt_drafts_url(status: "approved")

      assert_response :success
      assert_includes response.body, @draft.title
      assert_not_includes response.body, rejected.title
    end

    test "shows draft detail with prompt body" do
      get owner_codex_prompt_draft_url(@draft)

      assert_response :success
      assert_includes response.body, "Codex用プロンプト"
      assert_includes response.body, "db:drop / db:reset / drop database"
      assert_includes response.body, "Mark copied"
      assert_includes response.body, "Mark executed"
    end

    test "updates statuses" do
      assert_difference("OwnerDecisionLog.count", 1) do
        patch approve_owner_codex_prompt_draft_url(@draft)
      end
      assert_redirected_to owner_codex_prompt_draft_url(@draft)
      assert_equal "approved", @draft.reload.status
      assert_equal "approve", OwnerDecisionLog.last.decision_type

      assert_difference("OwnerDecisionLog.count", 1) do
        patch mark_copied_owner_codex_prompt_draft_url(@draft)
      end
      assert_redirected_to owner_codex_prompt_draft_url(@draft)
      assert_equal "copied", @draft.reload.status
      assert_equal "copied", OwnerDecisionLog.last.decision_type

      assert_difference("OwnerDecisionLog.count", 1) do
        patch mark_executed_owner_codex_prompt_draft_url(@draft)
      end
      assert_redirected_to owner_codex_prompt_draft_url(@draft)
      assert_equal "executed", @draft.reload.status
      assert_equal "executed", OwnerDecisionLog.last.decision_type

      assert_difference("OwnerDecisionLog.count", 1) do
        patch reject_owner_codex_prompt_draft_url(@draft)
      end
      assert_redirected_to owner_codex_prompt_drafts_url(status: "rejected")
      assert_equal "rejected", @draft.reload.status
      assert_equal "reject", OwnerDecisionLog.last.decision_type
    end
  end
end

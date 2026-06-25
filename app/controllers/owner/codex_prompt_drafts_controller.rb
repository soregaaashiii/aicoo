module Owner
  class CodexPromptDraftsController < ApplicationController
    before_action :set_codex_prompt_draft, only: %i[show approve reject mark_copied mark_executed]

    def index
      @status = params[:status]
      @codex_prompt_drafts = CodexPromptDraft.includes(:business, :action_candidate)
                                             .for_status(@status)
                                             .recent
                                             .limit(100)
    end

    def show
    end

    def approve
      previous_status = @codex_prompt_draft.status
      @codex_prompt_draft.approve!
      record_decision!("approve", previous_status:)
      redirect_to owner_codex_prompt_draft_path(@codex_prompt_draft), notice: "Codex Prompt Draftをapprovedにしました。"
    end

    def reject
      previous_status = @codex_prompt_draft.status
      @codex_prompt_draft.reject!
      record_decision!("reject", previous_status:)
      redirect_to owner_codex_prompt_drafts_path(status: "rejected"), notice: "Codex Prompt Draftをrejectedにしました。"
    end

    def mark_copied
      previous_status = @codex_prompt_draft.status
      @codex_prompt_draft.mark_copied!
      record_decision!("copied", previous_status:)
      redirect_to owner_codex_prompt_draft_path(@codex_prompt_draft), notice: "Codex Prompt Draftをcopiedにしました。"
    end

    def mark_executed
      previous_status = @codex_prompt_draft.status
      @codex_prompt_draft.mark_executed!
      record_decision!("executed", previous_status:)
      redirect_to owner_codex_prompt_draft_path(@codex_prompt_draft), notice: "Codex Prompt Draftをexecutedにしました。"
    end

    private

    def set_codex_prompt_draft
      @codex_prompt_draft = CodexPromptDraft.find(params.expect(:id))
    end

    def record_decision!(decision_type, previous_status:)
      OwnerDecisionLog.record!(
        subject: @codex_prompt_draft,
        decision_type:,
        decision_source: "codex_prompt_detail",
        previous_status:,
        new_status: @codex_prompt_draft.status
      )
    end
  end
end

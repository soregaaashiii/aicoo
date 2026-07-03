module Owner
  class ApprovedQueueController < ApplicationController
    def index
      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    def queue_selected
      candidates = ActionCandidate.where(id: params[:action_candidate_ids].to_a)
      Aicoo::ApprovalService.approve_all(candidates, operator: "owner", source: "legacy_approved_queue")

      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    def queue_all
      Aicoo::ApprovalService.approve_all(ActionCandidate.where(status: "approved"), operator: "owner", source: "legacy_approved_queue")

      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    private

    def integration_message
      "承認済みキューはAutoRevisionTaskへ統合しました。承認後のCodex Prompt確認・実行待ちはここで管理します。"
    end
  end
end

module Owner
  class ApprovedQueueController < ApplicationController
    def index
      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    def queue_selected
      AicooExecutor::ApprovedCandidateQueuer.queue_selected!(params[:action_candidate_ids].to_a)

      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    def queue_all
      AicooExecutor::ApprovedCandidateQueuer.queue_all!

      redirect_to auto_revision_tasks_path(status: "waiting_approval"),
                  notice: integration_message
    end

    private

    def integration_message
      "承認済みキューはAutoRevisionTaskへ統合しました。承認後のCodex Prompt確認・実行待ちはここで管理します。"
    end
  end
end

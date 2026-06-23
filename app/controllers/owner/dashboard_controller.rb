module Owner
  class DashboardController < ApplicationController
    def show
      @mode = params[:mode].presence_in(%w[balanced revenue learning]) || "balanced"
      @dashboard_summary = DashboardSummaryService.new(owner_mode: @mode, current_mode: "ceo").call
      @owner_task_inbox = Aicoo::OwnerTaskInbox.new.call
      @owner_task_digest = Aicoo::OwnerTaskDigest.new(owner_task_inbox: @owner_task_inbox).call
      @owner_task_completion_logs = OwnerTaskCompletionLog.recent.limit(3)
    end
  end
end

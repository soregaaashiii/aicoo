module Owner
  class TasksController < ApplicationController
    def index
      @priority = params[:priority].presence_in(Aicoo::OwnerTaskInbox::PRIORITY_ORDER.keys)
      @task_type = params[:task_type].presence_in(Aicoo::OwnerTaskInbox::TASK_TYPE_LABELS.keys)
      @owner_task_inbox = Aicoo::OwnerTaskInbox.new.call
      @owner_task_digest = Aicoo::OwnerTaskDigest.new(owner_task_inbox: @owner_task_inbox).call
      @owner_focus_home = Aicoo::OwnerFocusHome.new(owner_task_inbox: @owner_task_inbox).call
      @owner_execution_queue_summary = Aicoo::OwnerExecutionQueueSummary.new.call
      @owner_decision_summary = Aicoo::OwnerDecisionSummary.new.call
      @tasks = @owner_task_inbox.filtered(priority: @priority, task_type: @task_type)
      @owner_task_completion_logs = OwnerTaskCompletionLog.recent.limit(10)
    end
  end
end

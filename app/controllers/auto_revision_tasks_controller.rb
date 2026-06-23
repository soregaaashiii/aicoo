class AutoRevisionTasksController < ApplicationController
  before_action :set_auto_revision_task, only: %i[show approve record_result]

  def index
    @auto_revision_tasks = AutoRevisionTask.includes(:business, :action_candidate).by_priority.limit(100)
  end

  def show
  end

  def create
    action_candidate = ActionCandidate.find(params[:action_candidate_id])
    task = AutoRevisionTask.from_action_candidate(action_candidate)

    redirect_to task, notice: "Auto Revision Taskを作成しました。"
  end

  def approve
    @auto_revision_task.approve!
    redirect_to @auto_revision_task, notice: "Auto Revision Taskを承認しました。"
  end

  def record_result
    @auto_revision_task.record_result!(auto_revision_task_result_params)
    execution_log = create_action_execution_log_if_requested
    notice = execution_log ? "実装結果を登録し、ActionExecutionLogを作成しました。" : "実装結果を登録しました。"

    redirect_to @auto_revision_task, notice:
  end

  private

  def set_auto_revision_task
    @auto_revision_task = AutoRevisionTask.find(params.expect(:id))
  end

  def auto_revision_task_result_params
    params.expect(
      auto_revision_task: [
        :status,
        :result_summary,
        :error_message,
        :changed_files,
        :test_result,
        :codex_output,
        :finished_at
      ]
    )
  end

  def create_action_execution_log_if_requested
    return unless params[:create_action_execution_log] == "1"

    @auto_revision_task.create_action_execution_log!
  end
end

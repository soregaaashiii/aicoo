class AutoRevisionTasksController < ApplicationController
  before_action :set_auto_revision_task, only: %i[
    show
    approve
    cancel
    mark_sent_to_codex
    start_implementation
    update_codex_tracking
    record_result
    export_codex_prompt
  ]

  def index
    @auto_revision_tasks = AutoRevisionTask.includes(:business, :action_candidate).by_priority.limit(100)
  end

  def codex_queue
    @status_filter = params[:status].presence
    @auto_revision_tasks = codex_queue_scope.includes(:business, :action_candidate).limit(100)
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

  def cancel
    @auto_revision_task.update!(status: "canceled", finished_at: Time.current)
    redirect_back fallback_location: auto_revision_tasks_path, notice: "Auto Revision Taskをキャンセルしました。"
  end

  def mark_sent_to_codex
    @auto_revision_task.mark_sent_to_codex!
    redirect_back fallback_location: codex_queue_auto_revision_tasks_path, notice: "Codex投入済みにしました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: codex_queue_auto_revision_tasks_path,
                  alert: "Codex投入前のTarget Validationに失敗しました: #{e.record.errors.full_messages.to_sentence}"
  end

  def start_implementation
    @auto_revision_task.start_implementation!
    redirect_back fallback_location: codex_queue_auto_revision_tasks_path, notice: "実装開始にしました。"
  end

  def update_codex_tracking
    attributes = codex_tracking_params
    attributes[:last_checked_at] = Time.current if params[:mark_checked] == "1"
    @auto_revision_task.update!(attributes)

    redirect_to @auto_revision_task, notice: "Codex実行追跡情報を保存しました。"
  end

  def record_result
    @auto_revision_task.record_result!(auto_revision_task_result_params)
    execution_log = create_action_execution_log_if_requested
    notice = execution_log ? "実装結果を登録し、ActionExecutionLogを作成しました。" : "実装結果を登録しました。"

    redirect_to @auto_revision_task, notice:
  end

  def export_codex_prompt
    @target_validation = @auto_revision_task.codex_prompt_target_validation
    if @target_validation.invalid?
      render :export_codex_prompt, status: :unprocessable_content
      return
    end

    @auto_revision_task.record_codex_prompt_export!
    @markdown = @auto_revision_task.codex_prompt_markdown
    return unless params[:download] == "1"

    send_data @markdown,
              filename: @auto_revision_task.codex_prompt_export_filename,
              type: "text/markdown; charset=utf-8",
              disposition: "attachment"
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

  def codex_tracking_params
    params.expect(
      auto_revision_task: [
        :codex_thread_url,
        :codex_session_label,
        :last_checked_at
      ]
    )
  end

  def codex_queue_scope
    base_scope = AutoRevisionTask.codex_queue
    case @status_filter
    when "ready_for_codex", "sent_to_codex", "running"
      base_scope.where(status: @status_filter)
    when "stale"
      AutoRevisionTask.stale_codex.by_priority
    else
      base_scope
    end
  end

  def create_action_execution_log_if_requested
    return unless params[:create_action_execution_log] == "1"

    @auto_revision_task.create_action_execution_log!
  end
end

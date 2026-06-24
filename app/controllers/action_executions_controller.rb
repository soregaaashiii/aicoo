class ActionExecutionsController < ApplicationController
  before_action :set_action_execution

  def show
  end

  def start
    @action_execution.start!
    record_completion_log!("実行開始", "ActionExecution『#{@action_execution.action_candidate.title}』を開始しました。")
    redirect_to @action_execution, notice: "実行を開始しました。"
  end

  def complete
    @action_execution.complete!(
      actual_hours: action_execution_params[:actual_hours],
      actual_cost_yen: action_execution_params[:actual_cost_yen],
      result_summary: action_execution_params[:result_summary]
    )
    record_completion_log!("完了", "ActionExecution『#{@action_execution.action_candidate.title}』を完了しました。")
    redirect_to @action_execution, notice: "実行を完了しました。結果登録へ進めます。"
  end

  def fail
    @action_execution.fail!(result_summary: action_execution_params[:result_summary])
    record_completion_log!("失敗", "ActionExecution『#{@action_execution.action_candidate.title}』を失敗として記録しました。", result: "failed")
    redirect_to @action_execution, alert: "実行失敗を記録しました。"
  end

  def cancel
    @action_execution.cancel!
    record_completion_log!("キャンセル", "ActionExecution『#{@action_execution.action_candidate.title}』をキャンセルしました。", result: "skipped")
    redirect_to @action_execution, notice: "実行をキャンセルしました。"
  end

  private

  def set_action_execution
    @action_execution = ActionExecution.find(params.expect(:id))
  end

  def action_execution_params
    params.fetch(:action_execution, {}).permit(:actual_hours, :actual_cost_yen, :result_summary)
  end

  def record_completion_log!(label, message, result: "success")
    OwnerTaskCompletionLog.record!(
      task_type: "action_execution_ready",
      target: @action_execution,
      action_label: label,
      action_result: result,
      message:,
      metadata: {
        status: @action_execution.status,
        action_candidate_id: @action_execution.action_candidate_id
      }
    )
  end
end

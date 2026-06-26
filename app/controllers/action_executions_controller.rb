class ActionExecutionsController < ApplicationController
  before_action :set_action_execution

  def show
  end

  def start
    @action_execution.start!
    record_completion_log!("実行開始", "ActionExecution『#{@action_execution.action_candidate.title}』を開始しました。")
    redirect_to action_execution_path(@action_execution, anchor: "execution-result-form"), notice: "作業中にしました。完了時は実際に行った内容を入力してください。"
  end

  def complete
    @action_execution.complete!(
      actual_hours: action_execution_params[:actual_hours],
      actual_cost_yen: action_execution_params[:actual_cost_yen],
      result_summary: execution_result_summary
    )
    store_execution_result_intake!
    record_completion_log!("完了", "ActionExecution『#{@action_execution.action_candidate.title}』を完了しました。")
    redirect_to @action_execution, notice: "実行を完了しました。結果登録へ進めます。"
  end

  def fail
    @action_execution.fail!(result_summary: execution_result_summary)
    store_execution_result_intake!
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
    params.fetch(:action_execution, {}).permit(
      :actual_hours,
      :actual_cost_yen,
      :result_summary,
      :execution_outcome,
      :extra_work,
      :blocked_reason,
      completed_task_names: []
    )
  end

  def execution_result_summary
    [
      execution_outcome_label,
      action_execution_params[:result_summary].presence,
      action_execution_params[:extra_work].present? && "指示以上にやったこと: #{action_execution_params[:extra_work]}",
      action_execution_params[:blocked_reason].present? && "止まった理由: #{action_execution_params[:blocked_reason]}",
      completed_task_names.any? && "実施した作業: #{completed_task_names.join(' / ')}"
    ].compact.join("\n")
  end

  def execution_outcome_label
    case action_execution_params[:execution_outcome]
    when "as_planned" then "指示通りに完了"
    when "partial" then "一部だけ完了"
    when "exceeded" then "指示以上に実施"
    when "blocked" then "途中で止まった"
    else nil
    end
  end

  def completed_task_names
    Array(action_execution_params[:completed_task_names]).compact_blank
  end

  def store_execution_result_intake!
    @action_execution.update!(
      metadata: @action_execution.metadata.to_h.merge(
        "execution_result_intake" => {
          "execution_outcome" => action_execution_params[:execution_outcome],
          "execution_outcome_label" => execution_outcome_label,
          "completed_task_names" => completed_task_names,
          "extra_work" => action_execution_params[:extra_work],
          "blocked_reason" => action_execution_params[:blocked_reason],
          "recorded_at" => Time.current.iso8601
        }
      )
    )
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

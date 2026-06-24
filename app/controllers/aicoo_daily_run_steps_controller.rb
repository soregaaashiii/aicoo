class AicooDailyRunStepsController < ApplicationController
  def recover
    daily_run = AicooDailyRun.find(params[:aicoo_daily_run_id])
    step = daily_run.aicoo_daily_run_steps.find(params[:id])
    result = Aicoo::StepRecoveryService.run!(daily_run:, step_name: step.step_name)

    if result.success
      message = "#{step.step_name} step を再実行しました。"
      OwnerTaskCompletionLog.record_success!(
        task_type: "daily_run_step_recovery",
        target: step,
        action_label: "Recover Step",
        message: result.message.presence || message,
        metadata: recovery_metadata(result, daily_run, step)
      )
      redirect_to aicoo_daily_run_path(daily_run, anchor: "step-breakdown"), notice: message
    else
      message = "#{step.step_name} step の再実行に失敗しました。"
      OwnerTaskCompletionLog.record!(
        task_type: "daily_run_step_recovery",
        target: step,
        action_label: "Recover Step",
        action_result: "failed",
        message: result.error_message.presence || result.message.presence || message,
        metadata: recovery_metadata(result, daily_run, step)
      )
      redirect_to aicoo_daily_run_path(daily_run, anchor: "step-breakdown"), alert: message
    end
  end

  private

  def recovery_metadata(result, daily_run, step)
    {
      daily_run_id: daily_run.id,
      step_name: step.step_name,
      duration_seconds: result.duration_seconds,
      error_message: result.error_message
    }
  end
end

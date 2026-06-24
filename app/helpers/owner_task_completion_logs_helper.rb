module OwnerTaskCompletionLogsHelper
  def owner_task_completion_log_target_label(log)
    case log.target_type
    when "ActionCandidate"
      "ActionCandidate ##{log.target_id}"
    when "ActionPredictionCalibration"
      "補正係数"
    when "AicooDailyRun"
      "Daily Run ##{log.target_id}"
    when "AicooDailyRunStep"
      "Daily Run Step ##{log.target_id}"
    when "ActionExecution"
      "ActionExecution ##{log.target_id}"
    else
      log.target_type.presence || "-"
    end
  end

  def owner_task_completion_log_target_path(log)
    case log.target_type
    when "ActionCandidate"
      action_candidate_path(log.target_id)
    when "ActionPredictionCalibration"
      admin_aicoo_calibration_path
    when "AicooDailyRun"
      aicoo_daily_run_path(log.target_id)
    when "AicooDailyRunStep"
      step = AicooDailyRunStep.find_by(id: log.target_id)
      aicoo_daily_run_path(step.aicoo_daily_run, anchor: "step-breakdown") if step
    when "ActionExecution"
      action_execution_path(log.target_id)
    end
  end
end

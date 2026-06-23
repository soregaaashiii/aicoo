class AicooDailyRunsController < ApplicationController
  def index
    @daily_runs = AicooDailyRun.recent.limit(50)
  end

  def show
    @daily_run = AicooDailyRun.find(params[:id])
    @correction_readiness = AicooCorrectionReadinessService.new.call
    @execution_feasibility_insight = AicooExecutionFeasibilityInsightService.new.call
    @execution_feasibility_correction_overview = AicooExecutionFeasibilityCorrectionOverviewService.new.call
    @learning_loop_summary = AicooLearningLoopSummaryService.new.call
    @learning_loop_action_center = AicooLearningLoopActionCenterService.new.call
    @auto_revision_queue_run = @daily_run.auto_revision_queue_run
    @auto_revision_candidates = ActionCandidate.includes(:business)
                                               .active_for_ranking
                                               .where(created_at: @daily_run.target_date.all_day)
                                               .where.not(execution_prompt: [ nil, "" ])
                                               .order(final_score: :desc, created_at: :desc)
                                               .limit(5)
    @recent_auto_revision_tasks = AutoRevisionTask.includes(:business, :action_candidate).recent.limit(5)
  end

  def create
    target_date = daily_run_target_date
    daily_run = AicooDailyRunner.run!(target_date:, source: "manual")

    if daily_run.running?
      message = "#{target_date} のDaily Runはすでに実行中のため、再実行をスキップしました。"
      OwnerTaskCompletionLog.record!(
        task_type: "daily_run_failure",
        target: daily_run,
        action_label: "再実行",
        action_result: "skipped",
        message:,
        metadata: { target_date:, status: daily_run.status }
      )
      redirect_to daily_run, alert: message
    else
      message = "Daily Runを再実行しました。結果はDaily Run詳細で確認してください。"
      OwnerTaskCompletionLog.record_success!(
        task_type: daily_run.status == "partial_failed" ? "daily_run_partial_failed" : "daily_run_failure",
        target: daily_run,
        action_label: "再実行",
        message:,
        metadata: { target_date:, status: daily_run.status }
      )
      redirect_to daily_run, notice: message
    end
  rescue Date::Error => e
    redirect_back fallback_location: aicoo_daily_runs_path, alert: "AICOO Daily Runの対象日が不正です: #{e.message}"
  rescue StandardError => e
    redirect_back fallback_location: aicoo_daily_runs_path, alert: "AICOO Daily Runに失敗しました: #{e.message}"
  end

  private

  def daily_run_target_date
    value = params.dig(:aicoo_daily_run, :target_date).presence || params[:target_date].presence
    value.present? ? Date.parse(value) : Date.yesterday
  end
end

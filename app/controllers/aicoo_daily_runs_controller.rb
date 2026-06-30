class AicooDailyRunsController < ApplicationController
  def index
    @daily_runs = filtered_daily_runs.includes(:aicoo_daily_run_steps).limit(50)
    @comparison_rows = Aicoo::DailyRunHistory.comparison_rows(limit: 10)
    @running_daily_runs = AicooDailyRun.running.includes(:aicoo_daily_run_steps).recent
  end

  def show
    @daily_run = AicooDailyRun.find(params[:id])
    @daily_run_steps = @daily_run.aicoo_daily_run_steps.order(:started_at, :created_at)
    @daily_run_history = Aicoo::DailyRunHistory.new(@daily_run)
    @comparison_rows = Aicoo::DailyRunHistory.comparison_rows(limit: 10)
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

  def filtered_daily_runs
    scope = AicooDailyRun.recent
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(source: params[:source]) if params[:source].present?
    scope = scope.where(target_date: Date.parse(params[:date])) if params[:date].present?
    scope = scope.where(id: step_ids_for_status("failed")) if params[:failed].present?
    scope = scope.where(id: warning_step_ids) if params[:warning].present?
    scope = scope.where(id: step_ids_for_name("analytics_fetch")) if params[:analytics].present?
    scope = scope.where(id: step_ids_for_name_prefix("serp")) if params[:serp].present?
    scope = scope.where(id: step_ids_for_business(params[:business_id])) if params[:business_id].present?
    scope
  rescue Date::Error
    AicooDailyRun.none
  end

  def step_ids_for_status(status)
    AicooDailyRunStep.where(status:).select(:aicoo_daily_run_id)
  end

  def warning_step_ids
    AicooDailyRunStep.where("metadata ->> 'warning' = ? OR metadata ->> 'reason' IN (?)", "true", %w[
      serp_optional_missing
      analytics_optional_unavailable
    ]).select(:aicoo_daily_run_id)
  end

  def step_ids_for_name(step_name)
    AicooDailyRunStep.where(step_name:).select(:aicoo_daily_run_id)
  end

  def step_ids_for_name_prefix(prefix)
    AicooDailyRunStep.where("step_name LIKE ?", "#{prefix}%").select(:aicoo_daily_run_id)
  end

  def step_ids_for_business(business_id)
    AicooDailyRunStep.where("metadata ->> 'business_id' = ?", business_id.to_s).select(:aicoo_daily_run_id)
  end
end

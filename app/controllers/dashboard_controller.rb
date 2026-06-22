class DashboardController < ApplicationController
  def show
    @dashboard_summary = DashboardSummaryService.new.call
    @department_ranking = ActionCandidateDepartmentRanking.new(limit: 10).call
    @department_precision_summaries = ActionResultDepartmentSummary.new.summaries
    @aicoo_completion_levels = AicooCompletionLevelSummary.new.levels
    ranking_scope = dashboard_ranking_scope
    @expected_value_rankings = ranking_scope.by_expected_value
    @recommendation_rankings = ranking_scope.by_recommendation
    @business_summaries = Business.includes(:action_candidates, :revenue_events, :business_metric_dailies).order(:name).map do |business|
      BusinessSummary.new(business)
    end
    @business_summaries = sort_business_summaries(@business_summaries)
    @data_statuses = Business.includes(data_sources: :data_imports).order(:name).map { |business| DataStatus.new(business) }
    @ai_analysis_statuses = Business.includes(:ai_evaluation_runs).order(:name).map { |business| AiAnalysisStatus.new(business) }
    @aicoo_lab_candidate_summary = AicooLabCandidateSummary.new
    @aicoo_lab_landing_page_summary = AicooLabLandingPageSummary.new
    @aicoo_lab_experiment_summary = AicooLabExperimentSummary.new
    @aicoo_lab_metric_summary = AicooLabMetricSummary.new
    @aicoo_lab_generation_run_summary = AicooLabGenerationRunSummary.new
    @aicoo_lab_ai_draft_summary = AicooLabAiDraftSummary.new
    @aicoo_lab_flow_summary = AicooLabFlowSummary.new(@aicoo_lab_candidate_summary, @aicoo_lab_landing_page_summary, @aicoo_lab_experiment_summary)
    @aicoo_lab_next_actions = AicooLabNextActions.new(@aicoo_lab_candidate_summary, @aicoo_lab_experiment_summary).items
    @aicoo_lab_today_tasks = AicooLabTodayTasks.new.items
    @aicoo_lab_kpi_summary = AicooLabKpiSummary.new(@aicoo_lab_metric_summary)
    @aicoo_revenue_execution_summary = AicooRevenueExecutionSummary.new
    @aicoo_datahub_summary = AicooDataHubSummary.new
    @prediction_source_summary = PredictionSourceSummary.new
    @aicoo_judge_summary = AicooJudgeSummary.new
    @action_result_summary = ActionResultSummary.new
    @proxy_score_global_weight = ProxyScoreWeight.current_global || ProxyScoreWeight.new(ProxyScoreWeight.default_attributes)
    @proxy_score_weight_summaries = Business.includes(:proxy_score_weight).order(:name).map do |business|
      ProxyScoreWeightSummary.new(business)
    end
    @recent_proxy_score_weight_logs = ProxyScoreWeightAdjustmentLog.includes(:business).order(adjusted_at: :desc).limit(10)
    @latest_aicoo_daily_run = AicooDailyRun.recent.first
  end

  def generate_ai_top10
    result = AiCrossBusinessTopActionsService.new.call

    redirect_to action_candidates_path, notice: "AI generated #{result.action_candidates.size} cross-business top action candidates."
  rescue OpenaiResponsesClient::MissingApiKeyError => e
    redirect_to dashboard_path, alert: e.message
  rescue OpenaiResponsesClient::Error, ActiveRecord::RecordInvalid => e
    redirect_to dashboard_path, alert: "AI cross-business TOP10 generation failed: #{e.message}"
  end

  def import_business_metrics_today
    import_business_metrics_for(Date.current, "今日")
  end

  def import_business_metrics_yesterday
    import_business_metrics_for(Date.yesterday, "昨日")
  end

  def backfill_business_metrics
    start_date = Date.parse(params[:start_date].to_s)
    end_date = Date.parse(params[:end_date].to_s)
    raise Date::Error, "終了日は開始日以降を指定してください" if end_date < start_date

    results = BusinessMetricDailyImporter.import_all_range!(start_date:, end_date:)
    redirect_to dashboard_path, notice: "#{start_date}〜#{end_date}の代理指標を#{results.size}件更新しました。"
  rescue Date::Error => e
    redirect_to dashboard_path, alert: "代理指標の期間バックフィルに失敗しました: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_path, alert: "代理指標の期間バックフィルに失敗しました: #{e.record.errors.full_messages.to_sentence}"
  end

  def generate_action_candidates_from_metrics
    results = MetricActionCandidateGenerator.generate_all!
    created_count = results.sum(&:created_count)
    skipped_count = results.sum { |result| result.skipped.size }

    redirect_to dashboard_path, notice: "代理指標から行動候補を#{created_count}件生成しました。スキップ: #{skipped_count}件"
  end

  def generate_correction_readiness_actions
    result = CorrectionReadinessActionCandidateGenerator.generate_all!

    redirect_to dashboard_path, notice: "補正できない理由から行動候補を#{result.created.size}件生成しました。スキップ: #{result.skipped}件"
  end

  def adjust_global_proxy_score_weights
    log = ProxyScoreWeightAdjuster.new.adjust_global!(start_date: 30.days.ago.to_date, end_date: Date.current)
    redirect_to dashboard_path, notice: "全体proxy_score重みを確認しました: #{log.reason}"
  end

  def adjust_all_business_proxy_score_weights
    logs = ProxyScoreWeightAdjuster.new.adjust_all_businesses!(start_date: 30.days.ago.to_date, end_date: Date.current)
    redirect_to dashboard_path, notice: "全事業のproxy_score重みを#{logs.size}件確認しました。"
  end

  private

  def dashboard_ranking_scope
    ActionCandidate.active_for_ranking.where.not(action_type: "data_preparation")
  end

  def import_business_metrics_for(date, label)
    results = BusinessMetricDailyImporter.import_all!(date:)
    redirect_to dashboard_path, notice: "#{label}の代理指標を#{results.size}事業分更新しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_path, alert: "代理指標の更新に失敗しました: #{e.record.errors.full_messages.to_sentence}"
  end

  def sort_business_summaries(summaries)
    case params[:business_sort]
    when "current_month_profit"
      summaries.sort_by { |summary| [ -summary.current_month_profit, summary.business.name ] }
    when "cumulative_profit"
      summaries.sort_by { |summary| [ -summary.cumulative_profit, summary.business.name ] }
    when "current_month_proxy_score"
      summaries.sort_by { |summary| [ -summary.current_month_proxy_score, summary.business.name ] }
    when "cumulative_proxy_score"
      summaries.sort_by { |summary| [ -summary.cumulative_proxy_score, summary.business.name ] }
    else
      summaries
    end
  end

  BusinessSummary = Data.define(:business) do
    def action_candidates
      business.action_candidates.reject { |action| ActionCandidate::INACTIVE_STATUSES.include?(action.status) }
    end

    def action_count
      action_candidates.size
    end

    def expected_profit_total
      action_candidates.sum { |action| action.expected_profit_yen.to_i }
    end

    def average_hourly_value
      values = action_candidates.filter_map(&:expected_hourly_value_yen)
      return nil if values.empty?

      values.sum / values.size
    end

    def final_score_total
      action_candidates.sum { |action| action.final_score.to_d }
    end

    def top_actions
      action_candidates.sort_by { |action| [ -(action.final_score || 0), -(action.expected_hourly_value_yen || 0) ] }.first(3)
    end

    def current_month_profit
      business.current_month_profit
    end

    def cumulative_profit
      business.cumulative_profit
    end

    def current_month_proxy_score
      business.current_month_proxy_score
    end

    def recent_7d_proxy_score
      business.recent_7d_proxy_score
    end

    def recent_30d_proxy_score
      business.recent_30d_proxy_score
    end

    def cumulative_proxy_score
      business.cumulative_proxy_score
    end

    def evaluation_focus
      business.evaluation_focus == "profit" ? "profit重視" : "proxy_score重視"
    end

    def current_month_metric_total(metric)
      business.current_month_metric_total(metric)
    end
  end

  DataStatus = Data.define(:business) do
    def data_source_count
      business.data_sources.size
    end

    def data_import_count
      business.data_imports.size
    end

    def last_imported_at
      business.data_imports.map(&:imported_at).compact.max
    end
  end

  ProxyScoreWeightSummary = Data.define(:business) do
    def weight
      business.current_proxy_score_weight
    end

    def confidence_score
      weight.confidence_score.to_i
    end

    def source_label
      weight.persisted? ? weight.source_type : "code_default"
    end
  end

  ActionResultSummary = Data.define do
    def pending_count
      ActionResult.where(evaluation_status: "pending").count
    end

    def evaluated_count
      evaluated_results.count
    end

    def average_prediction_error
      values = evaluated_results.filter_map(&:prediction_error_yen)
      return nil if values.empty?

      values.sum.to_d / values.size
    end

    def recent_evaluated
      ActionResult.includes(:action_candidate, :business)
                  .where(evaluation_status: "evaluated")
                  .order(updated_at: :desc)
                  .limit(5)
    end

    def hit_results
      evaluated_results.select { |result| result.prediction_error_rate.present? && result.prediction_error_rate <= 0.3 }.first(5)
    end

    def missed_results
      evaluated_results.select { |result| result.prediction_error_rate.present? && result.prediction_error_rate > 0.3 }.first(5)
    end

    private

    def evaluated_results
      @evaluated_results ||= ActionResult.includes(:action_candidate, :business)
                                         .where(evaluation_status: "evaluated")
                                         .order(updated_at: :desc)
                                         .to_a
    end
  end

  AiAnalysisStatus = Data.define(:business) do
    def latest_generation_at
      generation_runs.map(&:created_at).compact.max
    end

    def generated_action_count
      generation_runs.sum { |run| run.created_action_count.to_i }
    end

    def reevaluation_count
      business.ai_evaluation_runs.count { |run| run.created_action_count.to_i.zero? }
    end

    private

    def generation_runs
      business.ai_evaluation_runs.select { |run| run.created_action_count.to_i.positive? }
    end
  end

  AicooLabCandidateSummary = Data.define do
    def total_count
      AicooLabExperimentCandidate.count
    end

    def approval_pending_count
      AicooLabExperimentCandidate.where(status: "proposed").count
    end

    def converted_count
      AicooLabExperimentCandidate.where(status: "converted").count
    end

    def auto_generated_count
      AicooLabExperimentCandidate.where(generation_source: "rule_based").count
    end

    def recent_auto_generated_count
      AicooLabExperimentCandidate.where(generation_source: "rule_based", created_at: 7.days.ago..).count
    end
  end

  AicooLabGenerationRunSummary = Data.define do
    def total_count
      AicooLabGenerationRun.count
    end

    def recent_count
      AicooLabGenerationRun.where(created_at: 7.days.ago..).count
    end
  end

  AicooLabAiDraftSummary = Data.define do
    def total_count
      AicooLabAiDraft.count
    end

    def approval_pending_count
      AicooLabAiDraft.where(status: "draft").count
    end

    def imported_count
      AicooLabAiDraft.where(status: "imported").count
    end
  end

  AicooLabLandingPageSummary = Data.define do
    def created_count
      AicooLabLandingPage.count
    end

    def preview_ready_count
      AicooLabLandingPage.where(status: "preview_ready").count
    end

    def approval_pending_count
      AicooLabLandingPage.joins(:aicoo_lab_experiment).where(aicoo_lab_experiments: { status: "approval_pending" }).count
    end

    def auto_created_experiment_count
      AicooLabExperiment.joins(:aicoo_lab_landing_page)
                          .where(aicoo_lab_landing_pages: { generation_source: "candidate_conversion" })
                          .distinct
                          .count
    end
  end

  AicooLabExperimentSummary = Data.define do
    def review_queue_count
      AicooLabExperiment.review_queue.count
    end

    def preview_ready_count
      AicooLabExperiment.where(status: "preview_ready").count
    end

    def approval_pending_count
      AicooLabExperiment.where(approval_status: "pending").count
    end

    def approved_count
      AicooLabExperiment.where(approval_status: "approved").count
    end

    def rejected_count
      AicooLabExperiment.where(approval_status: "rejected").count
    end

    def approved_not_started_count
      AicooLabExperiment.approved_not_started.count
    end

    def running_count
      AicooLabExperiment.where(status: "running").count
    end

    def due_7d_count
      due_count(:score_due_7d_at, :scored_7d_at)
    end

    def due_30d_count
      due_count(:score_due_30d_at, :scored_30d_at)
    end

    def due_90d_count
      due_count(:score_due_90d_at, :scored_90d_at)
    end

    def scoring_queue_count
      due_7d_count + due_30d_count + due_90d_count
    end

    def formal_scored_experiment_count
      AicooLabExperiment.joins(:aicoo_lab_results).where(aicoo_lab_results: { is_formal_score: true }).distinct.count
    end

    private

    def due_count(due_column, scored_column)
      AicooLabExperiment.where(status: "running")
                         .where(scored_column => nil)
                         .where("#{due_column} <= ?", Time.current)
                         .count
    end
  end

  AicooLabMetricSummary = Data.define do
    def total_pv
      AicooLabLandingPageEvent.where(event_type: "view").count
    end

    def total_cta_click
      AicooLabLandingPageEvent.where(event_type: "cta_click").count
    end

    def total_signup
      AicooLabSignup.count
    end

    def sample_reached_experiment_count
      AicooLabExperiment.where("current_pv >= sample_pv_threshold").count
    end
  end

  AicooLabFlowSummary = Data.define(:candidate_summary, :landing_page_summary, :experiment_summary) do
    def candidate_count
      candidate_summary.total_count
    end

    def landing_page_converted_count
      landing_page_summary.auto_created_experiment_count
    end

    def review_waiting_count
      experiment_summary.review_queue_count
    end

    def approved_not_started_count
      experiment_summary.approved_not_started_count
    end

    def running_count
      experiment_summary.running_count
    end

    def scoring_queue_count
      experiment_summary.scoring_queue_count
    end

    def formal_scored_count
      experiment_summary.formal_scored_experiment_count
    end
  end

  AicooLabNextActions = Data.define(:candidate_summary, :experiment_summary) do
    CANDIDATE_MINIMUM = 10

    def items
      [
        low_candidate_action,
        proposed_candidate_action,
        review_queue_action,
        approved_action,
        scoring_action
      ].compact
    end

    private

    def low_candidate_action
      return if candidate_summary.total_count >= CANDIDATE_MINIMUM

      NextAction.new("候補が少ない", "候補を自動生成", :button, :generate_candidates)
    end

    def proposed_candidate_action
      return if candidate_summary.approval_pending_count.zero?

      NextAction.new("proposed候補あり", "一括LP化", :link, :candidates)
    end

    def review_queue_action
      return if experiment_summary.review_queue_count.zero?

      NextAction.new("preview_readyあり", "レビューキューへ", :link, :review_queue)
    end

    def approved_action
      return if experiment_summary.approved_not_started_count.zero?

      NextAction.new("approved未開始あり", "running開始へ", :link, :approved)
    end

    def scoring_action
      return if experiment_summary.scoring_queue_count.zero?

      NextAction.new("scoring_queueあり", "採点待ちへ", :link, :scoring_queue)
    end

    NextAction = Data.define(:reason, :label, :kind, :target)
  end

  AicooLabTodayTasks = Data.define do
    def items
      (candidate_tasks + review_tasks + approved_tasks + scoring_tasks)
        .sort_by { |task| [ -task.priority_score.to_d, task.sort_label ] }
        .first(5)
    end

    private

    def candidate_tasks
      AicooLabExperimentCandidate.where(status: "proposed").by_lab_priority.limit(5).map do |candidate|
        Task.new("候補", candidate.title, candidate.lab_priority_score, Rails.application.routes.url_helpers.admin_aicoo_lab_candidate_path(candidate))
      end
    end

    def review_tasks
      AicooLabExperiment.review_queue.limit(5).map do |experiment|
        Task.new("レビュー", experiment.title, experiment.lab_priority_score, Rails.application.routes.url_helpers.admin_aicoo_lab_review_queue_experiment_path(experiment))
      end
    end

    def approved_tasks
      AicooLabExperiment.where(approval_status: "approved").where.not(status: "running").by_lab_priority.limit(5).map do |experiment|
        Task.new("開始", experiment.title, experiment.lab_priority_score, Rails.application.routes.url_helpers.admin_aicoo_lab_approved_experiments_path)
      end
    end

    def scoring_tasks
      AicooLabExperiment.where(status: "running").where("score_due_7d_at <= ? OR score_due_30d_at <= ? OR score_due_90d_at <= ?", Time.current, Time.current, Time.current).by_lab_priority.limit(5).map do |experiment|
        Task.new("採点", experiment.title, experiment.lab_priority_score, Rails.application.routes.url_helpers.admin_aicoo_lab_scoring_queue_path)
      end
    end

    Task = Data.define(:kind, :title, :priority_score, :path) do
      def sort_label
        "#{kind}:#{title}"
      end
    end
  end

  AicooLabKpiSummary = Data.define(:metric_summary) do
    def scored_experiment_count
      AicooLabExperiment.joins(:aicoo_lab_results).distinct.count
    end

    def calibration_score
      AicooLabErrorMetric.average(:calibration_score)
    end

    def total_pv
      metric_summary.total_pv
    end

    def total_cta_click
      metric_summary.total_cta_click
    end

    def total_signup
      metric_summary.total_signup
    end

    def current_month_cost_yen
      AicooLabExperiment.where(started_at: Time.current.all_month).sum(:actual_cost_yen)
    end

    def monthly_budget_yen
      AicooLabSetting.current.monthly_budget_yen
    end
  end

  AicooRevenueExecutionSummary = Data.define do
    def planned_count
      AicooRevenueExecution.where(status: "planned").count
    end

    def done_count
      AicooRevenueExecution.where(status: "done").count
    end

    def scored_count
      AicooRevenueExecution.scored.count
    end

    def average_calibration_score
      AicooRevenueExecution.scored.average(:calibration_score)
    end

    def today_revenue_value
      AicooRevenue::PlanBuilder.new(
        available_minutes: AicooRevenue::RankingBuilder::DEFAULT_AVAILABLE_MINUTES,
        available_budget_yen: AicooRevenue::RankingBuilder::DEFAULT_AVAILABLE_BUDGET_YEN
      ).call.total_revenue_value_yen
    end

    def neglect_alert_count
      AicooRevenue::RankingBuilder.new.call.neglect_alerts.count
    end
  end

  AicooDataHubSummary = Data.define do
    def total_count
      AicooDataSnapshot.count
    end

    def today_count
      AicooDataSnapshot.today.count
    end

    def scoring_candidate_count
      AicooDataHub::ScoringCandidateFinder.new.call.count
    end

    def latest_collection_finished_at
      latest_collection_run&.finished_at
    end

    def latest_collection_snapshot_count
      latest_collection_run&.snapshot_count.to_i
    end

    def latest_analytics_fetch_finished_at
      latest_analytics_fetch_run&.finished_at
    end

    def latest_analytics_fetch_status
      latest_analytics_fetch_run&.status || "-"
    end

    def recent_analytics_fetch_count
      AnalyticsFetchRun.where(started_at: 7.days.ago..).count
    end

    def analytics_schedule_ready?
      analytics_schedule_readiness.ready
    end

    def analytics_site_count
      AicooAnalyticsSite.count
    end

    def gsc_connected_site_count
      AicooAnalyticsSite.where.not(gsc_site_url: [ nil, "" ]).count
    end

    def ga4_connected_site_count
      AicooAnalyticsSite.where.not(ga4_property_id: [ nil, "" ]).count
    end

    def successfully_fetched_site_count
      AicooAnalyticsSite.joins(:analytics_source_settings)
                        .merge(AnalyticsSourceSetting.joins(:analytics_fetch_runs).where(analytics_fetch_runs: { status: "success" }))
                        .distinct
                        .count
    end

    def google_credential_status
      AicooGoogleCredential.default&.connected? ? "接続済み" : "未接続"
    end

    def google_credential_site_count
      credential = AicooGoogleCredential.default
      return 0 unless credential

      AicooAnalyticsSite
        .joins(:analytics_source_settings)
        .where(analytics_source_settings: { google_credential_id: credential.id })
        .distinct
        .count
    end

    def analytics_gsc_missing_count
      AicooAnalyticsSite.where(gsc_site_url: [ nil, "" ]).count
    end

    def analytics_ga4_missing_count
      AicooAnalyticsSite.where(ga4_property_id: [ nil, "" ]).count
    end

    def auto_created_analytics_site_count
      AicooAnalyticsSite.where(auto_created: true).count
    end

    private

    def analytics_schedule_readiness
      @analytics_schedule_readiness ||= AicooAnalytics::ScheduleReadinessChecker.new.call
    end

    def latest_collection_run
      AicooDataHubCollectionRun.recent.first
    end

    def latest_analytics_fetch_run
      AnalyticsFetchRun.recent.first
    end
  end

  PredictionSourceSummary = Data.define do
    def lab_count
      count_for("lab")
    end

    def revenue_count
      count_for("revenue")
    end

    def human_count
      count_for("human")
    end

    private

    def count_for(source)
      AicooLabPrediction.where(prediction_source: source).count +
        AicooRevenueExecution.where(prediction_source: source).count
    end
  end

  AicooJudgeSummary = Data.define do
    def prediction_count
      analysis.prediction_count
    end

    def best_source
      analysis.winner&.prediction_source
    end

    def best_calibration_score
      analysis.winner&.average_calibration_score
    end

    private

    def analysis
      @analysis ||= AicooJudge::PredictionAnalyzer.new.call
    end
  end
end

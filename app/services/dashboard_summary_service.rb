class DashboardSummaryService
  Result = Data.define(
    :today,
    :judge,
    :top_business,
    :top_generation_source,
    :top_action_candidates,
    :score_snapshots,
    :correction_readiness,
    :data_preparation_tasks,
    :data_preparation_queue,
    :today_tasks,
    :owner_metrics,
    :owner_alerts,
    :business_rankings,
    :approval_queue,
    :learning_value_summary
  )
  Today = Data.define(
    :daily_run,
    :target_date,
    :status,
    :started_at,
    :action_candidates_generated_count,
    :action_results_evaluated_count,
    :proxy_score_change_rate,
    :revenue_total_yen,
    :profit_total_yen
  )
  Judge = Data.define(
    :summary,
    :top_generation_source,
    :top_action_type,
    :top_business
  )
  ScoreSnapshots = Data.define(:recorded_on, :rank_up, :rank_down, :largest_multiplier, :no_adjustment_count)
  DataPreparationQueue = Data.define(:approval_pending_count, :today_added_count, :auto_queue_enabled)
  OwnerMetrics = Data.define(:revenue_yen, :profit_yen, :proxy_score, :new_candidate_count, :evaluated_count, :published_lp_count, :daily_run_status)
  ApprovalQueue = Data.define(
    :action_candidate_count,
    :executor_task_count,
    :data_preparation_count,
    :approved_remaining_count,
    :today_approved_count,
    :today_executor_queued_count
  )
  LearningValueSummary = Data.define(:total_learning_value_yen, :learning_candidate_count)
  BusinessRanking = Data.define(:business, :expected_total_value_yen, :expected_revenue_value_yen, :expected_learning_value_yen)

  def initialize(owner_mode: "balanced")
    @owner_mode = owner_mode.presence_in(%w[balanced revenue learning]) || "balanced"
  end

  def call
    score_builder = AicooJudge::ActionCandidateScore.new
    Result.new(
      today: today_summary,
      judge: judge_summary,
      top_business: top_business_summary,
      top_generation_source: top_generation_source_summary,
      top_action_candidates: top_action_candidates(score_builder),
      score_snapshots: score_snapshot_summary,
      correction_readiness: AicooCorrectionReadinessService.new.call,
      data_preparation_tasks: data_preparation_tasks,
      data_preparation_queue: data_preparation_queue_summary,
      today_tasks: owner_today_tasks,
      owner_metrics: owner_metrics,
      owner_alerts: owner_alerts,
      business_rankings: owner_business_rankings,
      approval_queue: approval_queue_summary,
      learning_value_summary: learning_value_summary
    )
  end

  private

  attr_reader :owner_mode

  def today_summary
    daily_run = latest_daily_run
    target_date = daily_run&.target_date || latest_metric_date || Date.yesterday

    Today.new(
      daily_run:,
      target_date:,
      status: daily_run&.status || "未実行",
      started_at: daily_run&.started_at,
      action_candidates_generated_count: daily_run&.action_candidates_generated_count.to_i,
      action_results_evaluated_count: daily_run&.action_results_evaluated_count.to_i,
      proxy_score_change_rate: proxy_score_change_rate(target_date),
      revenue_total_yen: RevenueEvent.revenue.where(occurred_on: target_date).sum(:amount),
      profit_total_yen: profit_total_for(target_date)
    )
  end

  def judge_summary
    judge_result = action_judge_result
    Judge.new(
      summary: judge_result.overall_summary,
      top_generation_source: best_summary(judge_result.generation_source_summaries),
      top_action_type: best_summary(judge_result.action_type_summaries),
      top_business: best_summary(judge_result.business_summaries)
    )
  end

  def top_business_summary
    best_summary(action_judge_result.business_summaries)
  end

  def top_generation_source_summary
    best_summary(action_judge_result.generation_source_summaries)
  end

  def top_action_candidates(score_builder)
    ActionCandidate.active_for_ranking
                   .includes(:business)
                   .where.not(action_type: "data_preparation")
                   .to_a
                   .map { |action_candidate| score_builder.score_for(action_candidate) }
                   .sort_by { |score| [ -score.judge_adjusted_score.to_d, -score.action_candidate.expected_profit_yen.to_i ] }
                   .first(10)
  end

  def score_snapshot_summary
    recorded_on = ActionCandidateScoreSnapshot.maximum(:recorded_on) || Date.current
    scope = ActionCandidateScoreSnapshot.includes(:action_candidate, :business).for_date(recorded_on)

    ScoreSnapshots.new(
      recorded_on:,
      rank_up: scope.rank_up.limit(5),
      rank_down: scope.rank_down.limit(5),
      largest_multiplier: scope.largest_multiplier.limit(5),
      no_adjustment_count: scope.no_adjustment.count
    )
  end

  def data_preparation_tasks
    ActionCandidate.active_for_ranking
                   .includes(:business)
                   .where(action_type: "data_preparation")
                   .order(final_score: :desc, created_at: :desc)
                   .limit(10)
  end

  def data_preparation_queue_summary
    scope = AicooExecutorTask.data_preparation
    DataPreparationQueue.new(
      approval_pending_count: scope.approval_pending.count,
      today_added_count: scope.where(created_at: Time.current.all_day).count,
      auto_queue_enabled: AicooSetting.current.auto_queue_data_preparation_tasks?
    )
  end

  def owner_today_tasks
    owner_scope
      .sort_by { |candidate| [ -owner_sort_value(candidate), -candidate.confidence_score.to_i, candidate.title.to_s ] }
      .first(10)
  end

  def owner_sort_value(candidate)
    case owner_mode
    when "revenue"
      candidate.expected_revenue_value_yen.to_i
    when "learning"
      candidate.expected_learning_value_yen.to_i
    else
      candidate.expected_total_value_yen.to_i
    end
  end

  def owner_scope
    @owner_scope ||= ActionCandidate.active_for_ranking.includes(:business).where.not(action_type: "data_preparation").to_a
  end

  def owner_metrics
    today = Date.current
    OwnerMetrics.new(
      revenue_yen: RevenueEvent.revenue.where(occurred_on: today).sum(:amount),
      profit_yen: profit_total_for(today),
      proxy_score: proxy_score_total(today),
      new_candidate_count: ActionCandidate.where(created_at: Time.current.all_day).count,
      evaluated_count: ActionResult.evaluated.where(updated_at: Time.current.all_day).count,
      published_lp_count: AicooLabLandingPage.where(status: "published").count,
      daily_run_status: latest_daily_run&.status || "未実行"
    )
  end

  def owner_alerts
    correction_readiness = AicooCorrectionReadinessService.new.call
    alerts = correction_readiness.items.reject(&:ready).map do |item|
      "#{item.label}: #{item.current_count}/#{item.required_count}"
    end
    alerts << "学習停止リスク: 評価済みActionResultが不足しています" if ActionResult.evaluated.count < AicooCorrectionReadinessService::EVALUATED_REQUIRED
    alerts
  end

  def owner_business_rankings
    Business.includes(:action_candidates).order(:name).map do |business|
      active_actions = business.action_candidates.reject { |candidate| ActionCandidate::INACTIVE_STATUSES.include?(candidate.status) }
      BusinessRanking.new(
        business:,
        expected_total_value_yen: active_actions.sum(&:expected_total_value_yen),
        expected_revenue_value_yen: active_actions.sum(&:expected_revenue_value_yen),
        expected_learning_value_yen: active_actions.sum(&:expected_learning_value_yen)
      )
    end.sort_by { |ranking| [ -ranking.expected_total_value_yen.to_i, ranking.business.name ] }
  end

  def approval_queue_summary
    data_preparation_count = ActionCandidate.active_for_ranking.where(action_type: "data_preparation").count
    ApprovalQueue.new(
      action_candidate_count: ActionCandidate.active_for_ranking.where(status: %w[idea pending]).count,
      executor_task_count: AicooExecutorTask.approval_pending.count,
      data_preparation_count:,
      approved_remaining_count: ActionCandidate.where(status: "approved").count,
      today_approved_count: ActionCandidate.where(approved_at: Time.current.all_day).count,
      today_executor_queued_count: ActionCandidate.where(executor_queued_at: Time.current.all_day).count
    )
  end

  def learning_value_summary
    scope = ActionCandidate.active_for_ranking
    LearningValueSummary.new(
      total_learning_value_yen: scope.sum(:expected_learning_value_yen),
      learning_candidate_count: scope.where("expected_learning_value_yen > 0").count
    )
  end

  def latest_daily_run
    @latest_daily_run ||= AicooDailyRun.recent.first
  end

  def latest_metric_date
    BusinessMetricDaily.maximum(:recorded_on)
  end

  def profit_total_for(date)
    RevenueEvent.revenue.where(occurred_on: date).sum(:amount) -
      RevenueEvent.expense.where(occurred_on: date).sum(:amount)
  end

  def proxy_score_change_rate(target_date)
    current_score = proxy_score_total(target_date)
    previous_score = proxy_score_total(target_date - 1.day)
    return nil if previous_score.zero?

    (current_score - previous_score) / previous_score
  end

  def proxy_score_total(date)
    BusinessMetricDaily.includes(:business)
                       .where(recorded_on: date)
                       .sum(&:proxy_score)
                       .to_d
  end

  def action_judge_result
    @action_judge_result ||= AicooJudge::ActionResultJudge.new(
      start_date: 30.days.ago.to_date,
      end_date: Date.current
    ).call
  end

  def best_summary(summaries)
    summaries
      .select { |summary| summary.evaluated_count.positive? && summary.hit_rate.present? }
      .max_by { |summary| [ summary.hit_rate.to_d, summary.evaluated_count ] }
  end
end

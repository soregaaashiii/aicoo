class DashboardSummaryService
  Result = Data.define(:today, :judge, :top_business, :top_generation_source, :top_action_candidates, :score_snapshots, :correction_readiness, :data_preparation_tasks, :data_preparation_queue)
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
      data_preparation_queue: data_preparation_queue_summary
    )
  end

  private

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

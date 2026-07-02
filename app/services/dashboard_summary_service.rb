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
    :learning_value_summary,
    :owner_fallback_tasks,
    :learning_progress,
    :aicoo_maturity_score,
    :aicoo_maturity_label,
    :evaluator_confidence_summary,
    :current_mode,
    :mode_description,
    :show_system_navigation,
    :show_ceo_navigation
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
  EvaluatorConfidence = Data.define(:evaluator_type, :confidence_score, :weighted_contribution_score, :confidence_delta)
  LearningProgress = Data.define(
    :action_result_current,
    :action_result_required,
    :evaluated_current,
    :evaluated_required,
    :judge_status,
    :business_metric_current,
    :business_metric_required,
    :revenue_event_current,
    :revenue_event_required
  )

  def initialize(owner_mode: "balanced", current_mode: "system")
    @owner_mode = owner_mode.presence_in(%w[balanced revenue learning]) || "balanced"
    @current_mode = current_mode.presence_in(%w[ceo system]) || "system"
  end

  def call
    score_builder = AicooJudge::ActionCandidateScore.new
    fallback_tasks = owner_fallback_tasks
    learning_progress = learning_progress_summary
    maturity_score = aicoo_maturity_score(learning_progress)

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
      learning_value_summary: learning_value_summary,
      owner_fallback_tasks: fallback_tasks,
      learning_progress: learning_progress,
      aicoo_maturity_score: maturity_score,
      aicoo_maturity_label: aicoo_maturity_label(maturity_score),
      evaluator_confidence_summary: evaluator_confidence_summary,
      current_mode:,
      mode_description: mode_description,
      show_system_navigation: current_mode == "ceo",
      show_ceo_navigation: current_mode == "system"
    )
  end

  private

  attr_reader :owner_mode, :current_mode

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
    ensure_owner_minimum_candidates!

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
      candidate.final_expected_value_yen.to_i
    end
  end

  def owner_scope
    @owner_scope ||= ActionCandidate.active_for_ranking
                                    .includes(:business)
                                    .where(status: %w[idea pending])
                                    .to_a
  end

  def owner_metrics
    today = Date.current
    OwnerMetrics.new(
      revenue_yen: RevenueEvent.revenue.where(occurred_on: today).sum(:amount),
      profit_yen: profit_total_for(today),
      proxy_score: proxy_score_total(today),
      new_candidate_count: ActionCandidate.where(created_at: Time.current.all_day).count,
      evaluated_count: ActionResult.evaluated.where(updated_at: Time.current.all_day).count,
      published_lp_count: AicooLabLandingPage.publicly_available.count,
      daily_run_status: latest_daily_run&.status || "未実行"
    )
  end

  def owner_alerts
    correction_readiness = AicooCorrectionReadinessService.new.call
    alerts = correction_readiness.items.reject(&:ready).map do |item|
      "#{owner_readiness_label(item.key)}: #{item.current_count}/#{item.required_count}"
    end
    alerts << "学習停止リスク: 評価済みの実行結果が不足しています" if ActionResult.evaluated.count < AicooCorrectionReadinessService::EVALUATED_REQUIRED
    alerts
  end

  def owner_business_rankings
    Business.real_businesses.includes(:action_candidates).order(:name).map do |business|
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
    codex_queue_statuses = AutoRevisionTask::CODEX_QUEUE_STATUSES
    ApprovalQueue.new(
      action_candidate_count: ActionCandidate.active_for_ranking.where(status: %w[idea pending]).count,
      executor_task_count: AutoRevisionTask.where(status: "waiting_approval").count,
      data_preparation_count:,
      approved_remaining_count: AutoRevisionTask.where(status: "waiting_approval").count,
      today_approved_count: ActionCandidate.where(approved_at: Time.current.all_day).count,
      today_executor_queued_count: AutoRevisionTask.where(status: codex_queue_statuses, updated_at: Time.current.all_day).count
    )
  end

  def learning_value_summary
    scope = ActionCandidate.active_for_ranking
    LearningValueSummary.new(
      total_learning_value_yen: scope.sum(:expected_learning_value_yen),
      learning_candidate_count: scope.where("expected_learning_value_yen > 0").count
    )
  end

  def evaluator_confidence_summary
    latest_date = MetaEvaluationSnapshot.global.maximum(:recorded_on)
    return evaluator_confidence_summary_from_candidates unless latest_date

    latest = MetaEvaluationSnapshot.global.for_date(latest_date).index_by(&:evaluator_type)
    previous_date = MetaEvaluationSnapshot.global.where(recorded_on: ...latest_date).maximum(:recorded_on)
    previous = previous_date ? MetaEvaluationSnapshot.global.for_date(previous_date).index_by(&:evaluator_type) : {}
    %w[gsc ga4 judge revenue learning].map do |evaluator_type|
      snapshot = latest[evaluator_type]
      previous_snapshot = previous[evaluator_type]
      confidence = snapshot&.average_confidence_score.to_d
      previous_confidence = previous_snapshot&.average_confidence_score.to_d
      EvaluatorConfidence.new(
        evaluator_type:,
        confidence_score: confidence.round,
        weighted_contribution_score: snapshot&.weighted_contribution_score.to_d,
        confidence_delta: previous_snapshot ? (confidence - previous_confidence).round : nil
      )
    end
  end

  def evaluator_confidence_summary_from_candidates
    breakdowns = ActionCandidate.active_for_ranking.limit(50).flat_map do |candidate|
      candidate.metadata.to_h.fetch("evaluator_breakdown", [])
    end

    %w[gsc ga4 judge revenue learning].map do |evaluator_type|
      entries = breakdowns.select { |entry| entry["evaluator_type"].to_s == evaluator_type }
      confidence = entries.any? ? (entries.sum { |entry| entry["confidence_score"].to_i }.to_d / entries.size).round : 0
      expected_value = entries.any? ? entries.sum { |entry| entry["expected_value_yen"].to_i }.to_d / entries.size : 0
      EvaluatorConfidence.new(
        evaluator_type:,
        confidence_score: confidence,
        weighted_contribution_score: expected_value * (confidence.to_d / 100),
        confidence_delta: nil
      )
    end
  end

  def owner_fallback_tasks
    ensure_owner_minimum_candidates!

    ActionCandidate.active_for_ranking
                   .includes(:business)
                   .where(status: %w[idea pending], action_type: "data_preparation")
                   .where("metadata ->> 'metric_rule' IN (?)", %w[correction_readiness owner_readiness])
                   .order(created_at: :desc)
                   .limit(10)
  end

  def learning_progress_summary
    evaluated_count = ActionResult.evaluated.count
    LearningProgress.new(
      action_result_current: ActionResult.count,
      action_result_required: AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED,
      evaluated_current: evaluated_count,
      evaluated_required: AicooCorrectionReadinessService::EVALUATED_REQUIRED,
      judge_status: evaluated_count >= AicooCorrectionReadinessService::EVALUATED_REQUIRED ? "稼働中" : "未開始",
      business_metric_current: BusinessMetricDaily.select(:recorded_on).distinct.count,
      business_metric_required: AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED,
      revenue_event_current: RevenueEvent.revenue.count,
      revenue_event_required: 10
    )
  end

  def aicoo_maturity_score(progress)
    score = 0
    score += capped_ratio(progress.action_result_current, progress.action_result_required) * 20
    score += capped_ratio(progress.evaluated_current, progress.evaluated_required) * 20
    score += capped_ratio(progress.business_metric_current, progress.business_metric_required) * 20
    score += capped_ratio(progress.revenue_event_current, progress.revenue_event_required) * 15
    score += 10 if AicooDailyRun.successful.exists?
    score += capped_ratio(ActionCandidateScoreSnapshot.count, 10) * 15
    score.round
  end

  def aicoo_maturity_label(score)
    case score
    when 0...25
      "初期学習段階"
    when 25...50
      "学習中"
    when 50...80
      "予測精度運用中"
    else
      "自走運用中"
    end
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

  def mode_description
    current_mode == "ceo" ? "意思決定専用画面" : "分析・運用・設定"
  end

  def ensure_owner_minimum_candidates!
    return if @owner_minimum_candidates_checked

    @owner_minimum_candidates_checked = true
    return if owner_scope.size >= 3

    CorrectionReadinessActionCandidateGenerator.generate_all!
    create_owner_readiness_candidates!
    @owner_scope = nil
  end

  def create_owner_readiness_candidates!
    business = Business.real_businesses.order(:created_at).first
    return unless business

    owner_readiness_templates.first(3).each do |template|
      next if recent_owner_readiness_duplicate?(business, template.fetch(:title))

      business.action_candidates.create!(
        title: template.fetch(:title),
        description: template.fetch(:description),
        action_type: "data_preparation",
        immediate_value_yen: 0,
        success_probability: 0.7,
        strategic_value_score: template.fetch(:strategic_value_score),
        risk_reduction_score: template.fetch(:risk_reduction_score),
        confidence_score: 70,
        data_confidence_score: 40,
        expected_hours: 1,
        cost_yen: 0,
        generation_source: "ai_business",
        metadata: {
          "metric_rule" => "owner_readiness",
          "missing_type" => template.fetch(:missing_type),
          "required_count" => { template.fetch(:missing_type) => template.fetch(:required_count) },
          "current_count" => { template.fetch(:missing_type) => template.fetch(:current_count) },
          "business_id" => business.id
        },
        evaluation_reason: template.fetch(:description),
        execution_prompt: template.fetch(:execution_prompt)
      )
    end
  end

  def owner_readiness_templates
    [
      {
        title: "実行結果を3件記録する",
        description: "予測精度を上げるため、実行済みの行動候補の結果を最低3件記録します。",
        missing_type: "action_results",
        required_count: 3,
        current_count: ActionResult.count,
        strategic_value_score: 70,
        risk_reduction_score: 80,
        execution_prompt: "実行済みの行動候補を3件選び、実行結果に実績利益・成長スコア差分・メモを記録してください。"
      },
      {
        title: "日次指標を30日分蓄積する",
        description: "成長スコアの時系列評価と重み補正を始めるため、日次指標を30日分取り込みます。",
        missing_type: "business_metric_daily",
        required_count: 30,
        current_count: BusinessMetricDaily.select(:recorded_on).distinct.count,
        strategic_value_score: 65,
        risk_reduction_score: 75,
        execution_prompt: "検索流入・サイト行動・LPイベントまたは手入力から、直近30日分の日次指標を取り込んでください。"
      },
      {
        title: "売上記録を10件入力する",
        description: "収益判断を始めるため、売上または費用を売上記録として入力します。",
        missing_type: "revenue_events",
        required_count: 10,
        current_count: RevenueEvent.revenue.count,
        strategic_value_score: 60,
        risk_reduction_score: 60,
        execution_prompt: "各事業の売上・費用を確認し、売上記録に売上または費用として記録してください。"
      }
    ]
  end

  def owner_readiness_label(key)
    {
      judge_data: "予測精度データ不足",
      action_results: "実行結果不足",
      evaluated: "評価済み実行結果不足",
      revenue: "売上記録不足",
      business_metric_daily: "日次指標不足"
    }.fetch(key, key.to_s)
  end

  def recent_owner_readiness_duplicate?(business, title)
    business.action_candidates
            .where(created_at: 7.days.ago..)
            .where(title:)
            .exists?
  end

  def capped_ratio(current, required)
    return 0 if required.to_i.zero?

    [ current.to_d / required.to_d, 1 ].min
  end
end

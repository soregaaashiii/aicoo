module Aicoo
  class LearningReportRecommendation
    Result = Data.define(:generated_at, :recommendations)
    Recommendation = Data.define(:priority, :category, :title, :reason, :recommended_action, :target_path, :metadata)

    def call
      Result.new(generated_at: Time.current, recommendations: recommendations.first(10))
    end

    private

    def recommendations
      [
        registration_rate_recommendation,
        learning_trend_recommendation,
        overestimation_recommendation,
        underestimation_recommendation,
        weakest_action_type_recommendation,
        action_type_gap_recommendation,
        calibration_recommendation,
        strong_discovery_source_recommendation,
        weak_discovery_source_recommendation
      ].compact.sort_by { |recommendation| priority_order.fetch(recommendation.priority, 99) }
    end

    def registration_rate_recommendation
      rate = learning_loop_health.registration_rate
      return if rate.nil? || rate >= 0.9.to_d

      Recommendation.new(
        priority: rate < 0.7.to_d ? "critical" : "high",
        category: "collect_more_results",
        title: "ActionResult登録を優先する",
        reason: "Learning Loop Completion Rateが#{(rate * 100).round(1)}%です。結果登録が不足すると補正が進みません。",
        recommended_action: "完了済みExecutionのActionResultを登録してください。",
        target_path: routes.owner_tasks_path(task_type: "action_result_registration"),
        metadata: { registration_rate: rate.to_s, missing_count: learning_loop_health.missing_count }
      )
    end

    def learning_trend_recommendation
      return unless quality_report.learning_trend == "declining"

      Recommendation.new(
        priority: "high",
        category: "learning_loop_missing",
        title: "Learning Trend低下を確認する",
        reason: "直近30日のAccuracy Scoreが前期間より低下しています。",
        recommended_action: "過大予測ランキングと苦手action_typeを確認し、評価式を保守的に調整してください。",
        target_path: routes.owner_learning_report_path,
        metadata: { learning_trend: quality_report.learning_trend }
      )
    end

    def overestimation_recommendation
      action = quality_report.most_overestimated_actions.first
      return unless action

      Recommendation.new(
        priority: "high",
        category: "reduce_overestimation",
        title: "#{action.action_candidate&.action_type || 'unknown'} の予測利益を保守化する",
        reason: "予測利益 #{action.predicted_profit.to_fs(:delimited)}円 に対して実績 #{action.actual_profit.to_fs(:delimited)}円でした。",
        recommended_action: "Calibration係数または成功確率を見直し、同種提案の予測を下げてください。",
        target_path: routes.action_result_path(action.action_result),
        metadata: action_metadata(action)
      )
    end

    def underestimation_recommendation
      action = quality_report.most_underestimated_actions.first
      return unless action

      Recommendation.new(
        priority: "medium",
        category: "review_underestimation",
        title: "#{action.action_candidate&.action_type || 'unknown'} の優先順位を見直す",
        reason: "予測利益 #{action.predicted_profit.to_fs(:delimited)}円 に対して実績 #{action.actual_profit.to_fs(:delimited)}円でした。",
        recommended_action: "過小評価されている可能性があります。類似候補の優先順位を上げる余地を確認してください。",
        target_path: routes.action_result_path(action.action_result),
        metadata: action_metadata(action)
      )
    end

    def weakest_action_type_recommendation
      summary = quality_report.weakest_action_types.first
      return unless summary

      Recommendation.new(
        priority: summary.avg_error_rate.to_d > 1 ? "high" : "medium",
        category: "improve_calibration",
        title: "#{summary.action_type} の評価式を改善する",
        reason: "#{summary.sample_count}件の平均誤差率が#{(summary.avg_error_rate.to_d * 100).round(1)}%です。",
        recommended_action: "ActionResultとRevenueEventを確認し、成功確率や期待利益の補正係数を見直してください。",
        target_path: routes.owner_learning_report_path,
        metadata: { action_type: summary.action_type, sample_count: summary.sample_count, avg_error_rate: summary.avg_error_rate.to_s }
      )
    end

    def action_type_gap_recommendation
      return if quality_report.total_evaluated.zero?

      missing_type = action_type_sample_counts.find { |_action_type, count| count < 2 }&.first
      return unless missing_type

      Recommendation.new(
        priority: "medium",
        category: "action_type_gap",
        title: "#{missing_type} の結果データを増やす",
        reason: "#{missing_type} の評価済みサンプルが不足しています。",
        recommended_action: "小さい施策を増やし、ActionResultを登録してください。",
        target_path: routes.action_candidates_path(action_type: missing_type),
        metadata: { action_type: missing_type, sample_count: action_type_sample_counts.fetch(missing_type, 0) }
      )
    end

    def calibration_recommendation
      return if quality_report.calibration_effectiveness_score != "N/A"

      Recommendation.new(
        priority: "low",
        category: "improve_calibration",
        title: "Calibration効果を測定できる状態にする",
        reason: "補正前後を比較するCalibrationログが不足しています。",
        recommended_action: "ActionResultを増やしたあと、評価関数補正を再計算してください。",
        target_path: routes.admin_aicoo_calibration_path,
        metadata: { calibration_effectiveness_score: "N/A" }
      )
    end

    def strong_discovery_source_recommendation
      source = discovery_source_report.strongest_sources.first
      return unless source

      Recommendation.new(
        priority: "medium",
        category: "discovery_source",
        title: "#{source.source_type} の発見を増やす",
        reason: "#{source.source_type} は実績利益 #{source.total_actual_profit.to_i.to_fs(:delimited)}円、成功率 #{(source.overall_success_rate * 100).round(1)}% です。",
        recommended_action: "同じ発見源から小さなOpportunityを増やし、ActionCandidate化してください。",
        target_path: routes.owner_discovery_report_path,
        metadata: { source_type: source.source_type, total_actual_profit: source.total_actual_profit, success_rate: source.overall_success_rate.to_s }
      )
    end

    def weak_discovery_source_recommendation
      source = discovery_source_report.weakest_sources.first
      return unless source
      return if source.overall_success_rate.to_d >= 0.5.to_d && source.total_actual_profit.to_i >= 0

      Recommendation.new(
        priority: source.total_actual_profit.to_i.negative? ? "high" : "medium",
        category: "discovery_source",
        title: "#{source.source_type} 系仮説の精度を見直す",
        reason: "#{source.source_type} は成功率 #{(source.overall_success_rate * 100).round(1)}%、実績利益 #{source.total_actual_profit.to_i.to_fs(:delimited)}円です。",
        recommended_action: "Opportunity化前の条件や検証粒度を見直してください。",
        target_path: routes.owner_discovery_report_path,
        metadata: { source_type: source.source_type, total_actual_profit: source.total_actual_profit, success_rate: source.overall_success_rate.to_s }
      )
    end

    def action_type_sample_counts
      @action_type_sample_counts ||= ActionCandidate::ACTION_TYPES.index_with do |action_type|
        ActionResult.evaluated.joins(:action_candidate).where(action_candidates: { action_type: }).count
      end
    end

    def action_metadata(action)
      {
        action_candidate_id: action.action_candidate&.id,
        action_result_id: action.action_result.id,
        action_type: action.action_candidate&.action_type,
        predicted_profit: action.predicted_profit,
        actual_profit: action.actual_profit,
        error_rate: action.error_rate.to_s
      }
    end

    def quality_report
      @quality_report ||= LearningLoopQualityReport.new.call
    end

    def learning_loop_health
      @learning_loop_health ||= LearningLoopHealthSummary.new.call
    end

    def discovery_source_report
      @discovery_source_report ||= DiscoverySourcePerformanceReport.new.call
    end

    def priority_order
      OwnerTaskInbox::PRIORITY_ORDER
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end

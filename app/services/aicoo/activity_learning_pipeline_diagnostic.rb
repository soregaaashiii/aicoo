require "set"

module Aicoo
  class ActivityLearningPipelineDiagnostic
    Stage = Data.define(:name, :status, :reason)
    Row = Data.define(
      :event_id,
      :business_id,
      :activity_type,
      :source_app,
      :received_at,
      :stages,
      :stop_reason,
      :action_result_id,
      :candidate_id
    )
    Summary = Data.define(
      :activity_api_received_count,
      :business_activity_log_count,
      :activity_evaluation_count,
      :activity_to_action_result_count,
      :action_result_auto_evaluated_count,
      :calibration_count,
      :learning_count,
      :expected_value_update_count,
      :today_reflected_count
    )
    Result = Data.define(:rows, :summary)

    def initialize(limit: 50, business_id: nil)
      @limit = limit.to_i.positive? ? limit.to_i : 50
      @business_id = business_id.presence
    end

    def call
      logs = scoped_logs.to_a
      today_candidate_ids = load_today_candidate_ids(logs)
      rows = logs.map { |log| row_for(log, today_candidate_ids) }
      Result.new(rows:, summary: summary_for(rows))
    end

    private

    attr_reader :limit, :business_id

    def scoped_logs
      scope = BusinessActivityLog.includes(:business, :activity_evaluations).order(occurred_at: :desc, id: :desc)
      scope = scope.where(business_id:) if business_id
      scope.limit(limit)
    end

    def row_for(log, today_candidate_ids)
      evaluation = latest_evaluation(log)
      action_result = action_result_for(evaluation)
      calibration = calibration_for(action_result)
      candidate = action_result&.action_candidate
      stages = [
        business_activity_log_stage(log),
        activity_evaluation_stage(log, evaluation),
        action_result_stage(evaluation, action_result),
        business_metric_stage(evaluation),
        calibration_stage(action_result, calibration),
        learning_stage(action_result, calibration),
        expected_value_stage(action_result),
        today_stage(candidate, today_candidate_ids)
      ]

      Row.new(
        event_id: log.id,
        business_id: log.business_id,
        activity_type: log.activity_type,
        source_app: log.source_app,
        received_at: log.detected_at,
        stages:,
        stop_reason: stages.find { |stage| stage.status == "FAIL" }&.reason,
        action_result_id: action_result&.id,
        candidate_id: candidate&.id
      )
    end

    def business_activity_log_stage(log)
      status = log.persisted? ? "PASS" : "FAIL"
      Stage.new(name: "BusinessActivityLog", status:, reason: status == "PASS" ? nil : "business_activity_log_missing")
    end

    def activity_evaluation_stage(log, evaluation)
      return Stage.new(name: "ActivityEvaluation", status: "WARNING", reason: "evaluation_not_due") if evaluation.blank? && !evaluation_due?(log)
      return Stage.new(name: "ActivityEvaluation", status: "FAIL", reason: "activity_evaluation_missing") if evaluation.blank?
      return Stage.new(name: "ActivityEvaluation", status: "PASS", reason: nil) if evaluation.evaluated?
      return Stage.new(name: "ActivityEvaluation", status: "WARNING", reason: "evaluation_pending") if evaluation.pending?

      Stage.new(name: "ActivityEvaluation", status: "FAIL", reason: evaluation.skip_reason.presence || "activity_evaluation_skipped")
    end

    def action_result_stage(evaluation, action_result)
      return Stage.new(name: "ActionResult", status: "WARNING", reason: "activity_evaluation_missing") unless evaluation
      return Stage.new(name: "ActionResult", status: "WARNING", reason: "activity_evaluation_not_evaluated") unless evaluation.evaluated?
      return Stage.new(name: "ActionResult", status: "PASS", reason: nil) if action_result&.evaluation_status == "evaluated"

      bridge = evaluation.metadata.to_h["action_result_bridge"].to_h
      Stage.new(name: "ActionResult", status: "FAIL", reason: bridge["reason"].presence || "action_result_not_generated")
    end

    def business_metric_stage(evaluation)
      return Stage.new(name: "BusinessMetricDaily", status: "WARNING", reason: "activity_evaluation_missing") unless evaluation
      return Stage.new(name: "BusinessMetricDaily", status: "PASS", reason: nil) if evaluation.evaluated?
      return Stage.new(name: "BusinessMetricDaily", status: "FAIL", reason: evaluation.skip_reason) if evaluation.skip_reason.present?

      Stage.new(name: "BusinessMetricDaily", status: "WARNING", reason: "metrics_not_evaluated_yet")
    end

    def calibration_stage(action_result, calibration)
      return Stage.new(name: "Calibration", status: "WARNING", reason: "action_result_missing") unless action_result
      return Stage.new(name: "Calibration", status: "PASS", reason: nil) if calibration

      Stage.new(name: "Calibration", status: "FAIL", reason: "calibration_missing")
    end

    def learning_stage(action_result, calibration)
      return Stage.new(name: "Learning", status: "WARNING", reason: "action_result_missing") unless action_result
      return Stage.new(name: "Learning", status: "PASS", reason: nil) if calibration

      Stage.new(name: "Learning", status: "FAIL", reason: "learning_not_available")
    end

    def expected_value_stage(action_result)
      return Stage.new(name: "ExpectedValue", status: "WARNING", reason: "action_result_missing") unless action_result

      metadata = action_result.metadata.to_h["activity_learning_pipeline"].to_h
      return Stage.new(name: "ExpectedValue", status: "PASS", reason: nil) if metadata["auto_generated"] == true

      Stage.new(name: "ExpectedValue", status: "WARNING", reason: "expected_value_refresh_not_marked")
    end

    def today_stage(candidate, today_candidate_ids)
      return Stage.new(name: "Today", status: "WARNING", reason: "action_candidate_missing") unless candidate
      return Stage.new(name: "Today", status: "PASS", reason: nil) if today_candidate_ids.include?(candidate.id)

      Stage.new(name: "Today", status: "WARNING", reason: "candidate_not_in_today_board")
    end

    def latest_evaluation(log)
      log.activity_evaluations.max_by do |evaluation|
        status_priority = { "evaluated" => 2, "pending" => 1, "skipped" => 0 }.fetch(evaluation.status, -1)
        [ status_priority, evaluation.evaluation_window_days.to_i, evaluation.id.to_i ]
      end
    end

    def action_result_for(evaluation)
      return unless evaluation

      bridge_result_id = evaluation.metadata.to_h.dig("action_result_bridge", "action_result_id")
      return ActionResult.includes(:action_candidate).find_by(id: bridge_result_id) if bridge_result_id.present?

      ActionResult.includes(:action_candidate).detect do |result|
        result.metadata.to_h.dig("activity_learning_pipeline", "activity_evaluation_id").to_i == evaluation.id
      end
    end

    def calibration_for(action_result)
      return unless action_result&.action_candidate

      candidate = action_result.action_candidate
      article_type = article_opportunity_calibration_action_type(candidate)
      ActionPredictionCalibration.find_by(action_type: article_type) ||
        ActionPredictionCalibration.find_by(action_type: candidate.action_type.presence || "other")
    end

    def article_opportunity_calibration_action_type(candidate)
      metadata = candidate.metadata.to_h
      return unless metadata["value_model_name"].to_s == Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME ||
        metadata.dig("expected_profit_model", "name").to_s == Aicoo::ArticleOpportunityExpectedProfit::MODEL_NAME ||
        metadata.dig("expected_profit_model", "value_model").to_s == "grounded_article_opportunity_profit"

      improvement_type = [
        metadata["opportunity_type"],
        metadata["improvement_type"],
        metadata.dig("expected_profit_model", "improvement_type"),
        metadata.dig("execution_brief", "target", "improvement_type")
      ].find(&:present?)
      "article_opportunity:#{improvement_type}" if improvement_type.present?
    end

    def evaluation_due?(log)
      log.occurred_at + Aicoo::ActivityEvaluationBuilder::WINDOWS.min.days <= Time.current
    end

    def load_today_candidate_ids(logs)
      candidate_ids = logs.filter_map do |log|
        latest_evaluation(log)&.metadata.to_h.dig("action_result_bridge", "action_result_id")
      end
      return Set.new if candidate_ids.empty?

      Aicoo::TodayActionBoard.new(per_page: 500).call.items.filter_map do |item|
        item.record.id if item.record.is_a?(ActionCandidate)
      end.to_set
    rescue StandardError => e
      Rails.logger.warn("[ActivityLearningPipeline] today_board_check_failed error=#{e.class}: #{e.message}")
      Set.new
    end

    def summary_for(rows)
      generated_action_results = activity_generated_action_results
      calibrations = ActionPredictionCalibration.count
      Summary.new(
        activity_api_received_count: BusinessActivityLog.where(source_method: "logger").count,
        business_activity_log_count: BusinessActivityLog.count,
        activity_evaluation_count: ActivityEvaluation.distinct.count(:business_activity_log_id),
        activity_to_action_result_count: generated_action_results.count,
        action_result_auto_evaluated_count: generated_action_results.count,
        calibration_count: calibrations,
        learning_count: calibrations,
        expected_value_update_count: generated_action_results.count,
        today_reflected_count: rows.count { |row| row.stages.find { |stage| stage.name == "Today" }&.status == "PASS" }
      )
    end

    def activity_generated_action_results
      ActionResult.evaluated.select do |result|
        result.metadata.to_h.dig("activity_learning_pipeline", "auto_generated") == true
      end
    end
  end
end

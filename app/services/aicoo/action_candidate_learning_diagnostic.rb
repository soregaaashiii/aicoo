module Aicoo
  class ActionCandidateLearningDiagnostic
    Row = Data.define(
      :candidate_id,
      :registered_count,
      :action_result_id,
      :action_result_status,
      :learning_available,
      :calibration_id,
      :expected_value_yen
    )
    Result = Data.define(:rows, :candidate_count, :evaluated_count, :learning_count)

    def initialize(business_id: nil, limit: 500)
      @business_id = business_id.presence
      @limit = limit.to_i.positive? ? limit.to_i : 500
    end

    def call
      rows = action_results.map { |result| row_for(result) }
      Result.new(
        rows:,
        candidate_count: rows.size,
        evaluated_count: rows.count { |row| row.action_result_status == "evaluated" },
        learning_count: rows.count(&:learning_available)
      )
    end

    private

    attr_reader :business_id, :limit

    def action_results
      scope = ActionResult.includes(:action_candidate).order(id: :desc)
      scope = scope.where(business_id:) if business_id
      scope.limit(limit)
    end

    def row_for(result)
      candidate = result.action_candidate
      calibration = calibration_for(candidate)
      Row.new(
        candidate_id: candidate.id,
        registered_count: result.metadata.to_h.dig("action_candidate_completion", "registered_count"),
        action_result_id: result.id,
        action_result_status: result.evaluation_status,
        learning_available: calibration.present?,
        calibration_id: calibration&.id,
        expected_value_yen: candidate.final_expected_value_yen
      )
    end

    def calibration_for(candidate)
      action_types = [ article_opportunity_action_type(candidate), candidate.action_type.presence || "other" ].compact
      ActionPredictionCalibration.find_by(action_type: action_types)
    end

    def article_opportunity_action_type(candidate)
      metadata = candidate.metadata.to_h
      improvement_type = [
        metadata["opportunity_type"],
        metadata["improvement_type"],
        metadata.dig("expected_profit_model", "improvement_type"),
        metadata.dig("execution_brief", "target", "improvement_type")
      ].find(&:present?)
      "article_opportunity:#{improvement_type}" if improvement_type.present?
    end
  end
end

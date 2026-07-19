module Aicoo
  class ExpectedValueLearningRefresh
    def self.refresh_after_action_result!(action_result, source:)
      return nil unless action_result&.evaluation_status == "evaluated"

      CalibrationEngine.run!(source:)
    rescue StandardError => e
      Rails.logger.warn("[ExpectedValueLearning] refresh failed action_result_id=#{action_result&.id} source=#{source} error=#{e.class}: #{e.message}")
      nil
    end
  end
end

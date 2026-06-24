module Aicoo
  class LearningLoopHealthSummary
    Result = Data.define(
      :completed_execution_count,
      :action_result_count,
      :registration_rate,
      :missing_count,
      :health_status,
      :health_message
    )

    WARNING_RATE = 0.9.to_d
    CRITICAL_RATE = 0.7.to_d

    def call
      Result.new(
        completed_execution_count:,
        action_result_count:,
        registration_rate:,
        missing_count:,
        health_status:,
        health_message:
      )
    end

    private

    def completed_execution_count
      @completed_execution_count ||= ActionExecution.where(status: "completed").count
    end

    def action_result_count
      @action_result_count ||= ActionExecution.where(status: "completed").joins(:action_result).count
    end

    def missing_count
      @missing_count ||= ActionExecution.completed_without_result.count
    end

    def registration_rate
      return nil if completed_execution_count.zero?

      action_result_count.to_d / completed_execution_count
    end

    def health_status
      return "healthy" if registration_rate.nil?
      return "critical" if registration_rate < CRITICAL_RATE
      return "warning" if registration_rate < WARNING_RATE

      "healthy"
    end

    def health_message
      return "完了済みExecutionがまだありません。" if registration_rate.nil?

      percentage = (registration_rate * 100).round(1)
      case health_status
      when "critical"
        "Learning Loop Completion Rate: #{percentage}%。ActionResult登録が不足しています。"
      when "warning"
        "Learning Loop Completion Rate: #{percentage}%。結果登録を増やしてください。"
      else
        "Learning Loop Completion Rate: #{percentage}%。"
      end
    end
  end
end

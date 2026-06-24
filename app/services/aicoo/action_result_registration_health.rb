module Aicoo
  class ActionResultRegistrationHealth
    Result = Data.define(
      :pending_count,
      :warning_count,
      :critical_count,
      :oldest_pending_at,
      :oldest_pending_hours,
      :average_delay_hours,
      :pending_execution_ids,
      :warning_execution_ids,
      :critical_execution_ids,
      :health_status,
      :health_message
    )

    WARNING_AFTER = 24.hours
    CRITICAL_AFTER = 72.hours

    def call
      Result.new(
        pending_count: executions.size,
        warning_count: warning_executions.size,
        critical_count: critical_executions.size,
        oldest_pending_at:,
        oldest_pending_hours: hours_since(oldest_pending_at),
        average_delay_hours:,
        pending_execution_ids: executions.map(&:id),
        warning_execution_ids: warning_executions.map(&:id),
        critical_execution_ids: critical_executions.map(&:id),
        health_status:,
        health_message:
      )
    end

    private

    def executions
      @executions ||= ActionExecution.completed_without_result.where.not(completed_at: nil).order(:completed_at).to_a
    end

    def warning_executions
      @warning_executions ||= executions.select do |execution|
        elapsed = elapsed_seconds(execution)
        elapsed >= WARNING_AFTER && elapsed < CRITICAL_AFTER
      end
    end

    def critical_executions
      @critical_executions ||= executions.select { |execution| elapsed_seconds(execution) >= CRITICAL_AFTER }
    end

    def oldest_pending_at
      executions.first&.completed_at
    end

    def average_delay_hours
      return if executions.empty?

      delays = executions.map { |execution| hours_since(execution.completed_at).to_d }
      delays.sum / delays.size
    end

    def health_status
      return "critical" if critical_executions.any?
      return "warning" if warning_executions.any?
      return "attention" if executions.any?

      "healthy"
    end

    def health_message
      case health_status
      when "critical"
        "結果登録が滞留しています。学習ループが止まる前にActionResultを登録してください。"
      when "warning"
        "24時間以上未登録のActionResultがあります。今日中に登録してください。"
      when "attention"
        "完了済みExecutionのActionResult登録待ちがあります。"
      else
        "ActionResult登録は正常です。"
      end
    end

    def elapsed_seconds(execution)
      Time.current - execution.completed_at
    end

    def hours_since(time)
      return unless time

      ((Time.current - time) / 1.hour).round(1)
    end
  end
end

module Aicoo
  class DailyRunStuckGuard
    MAX_STUCK_PER_STEP = 3

    Result = Data.define(:checked_count, :stuck_count, :partial_failed_count)

    def self.call(threshold:)
      new(threshold:).call
    end

    def initialize(threshold:)
      @threshold = threshold
      @stuck_count = 0
      @partial_failed_count = 0
    end

    def call
      checked_count = stale_running_runs.count
      stale_running_runs.find_each do |run|
        handle_stale_run!(run)
      end

      Result.new(
        checked_count:,
        stuck_count:,
        partial_failed_count:
      )
    end

    private

    attr_reader :threshold, :stuck_count, :partial_failed_count

    def stale_running_runs
      @stale_running_runs ||= AicooDailyRun.running
                                       .where(finished_at: nil)
                                       .where("started_at < ?", threshold.ago)
    end

    def handle_stale_run!(run)
      running_step = run.aicoo_daily_run_steps.where(status: "running").recent.first
      if running_step && previous_stuck_count_for(running_step.step_name) >= (MAX_STUCK_PER_STEP - 1)
        mark_step_failed!(run, running_step)
      else
        mark_run_stuck!(run, running_step)
      end
    end

    def previous_stuck_count_for(step_name)
      AicooDailyRunStep
        .joins(:aicoo_daily_run)
        .where(step_name:, status: "running", aicoo_daily_runs: { status: "stuck" })
        .distinct
        .count(:aicoo_daily_run_id)
    end

    def mark_step_failed!(run, step)
      finished_at = Time.current
      message = "同じStep(#{step.step_name})で#{MAX_STUCK_PER_STEP}回以上stuckしたため、このStepだけfailedにしました。"
      step.update!(
        status: "failed",
        finished_at:,
        duration_seconds: duration_seconds(step.started_at, finished_at),
        error_message: message,
        metadata: step.metadata.to_h.merge(
          "stuck_guard" => {
            "reason" => "same_step_stuck_limit_reached",
            "max_stuck_per_step" => MAX_STUCK_PER_STEP,
            "marked_at" => finished_at.iso8601
          }
        )
      )
      run.update!(
        status: "partial_failed",
        finished_at:,
        error_message: message,
        run_log: append_log(run.run_log, message)
      )
      @partial_failed_count += 1
    end

    def mark_run_stuck!(run, step)
      finished_at = Time.current
      message = if step
        "runningのまま#{threshold.inspect}を超過しました。last_step=#{step.step_name}"
      else
        "runningのまま#{threshold.inspect}を超過しました。running stepなし"
      end
      run.update!(
        status: "stuck",
        finished_at:,
        error_message: message,
        run_log: append_log(run.run_log, message)
      )
      @stuck_count += 1
    end

    def duration_seconds(started_at, finished_at)
      return unless started_at

      finished_at - started_at
    end

    def append_log(current_log, message)
      [ current_log.presence, "[#{Time.current.iso8601}] #{message}" ].compact.join("\n")
    end
  end
end

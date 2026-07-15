module Aicoo
  class DailyRunStuckGuard
    MAX_STUCK_PER_STEP = 3
    DEFAULT_ORPHAN_TIMEOUT_MINUTES = 15

    Result = Data.define(:checked_count, :stuck_count, :partial_failed_count)
    OrphanRow = Data.define(:run, :step, :last_heartbeat_at, :last_updated_at, :stale_minutes, :orphan)

    def self.call(threshold:)
      new(threshold:).call
    end

    def self.orphan_threshold
      minutes = ENV.fetch("DAILY_RUN_ORPHAN_TIMEOUT_MINUTES", DEFAULT_ORPHAN_TIMEOUT_MINUTES).to_i
      (minutes.positive? ? minutes : DEFAULT_ORPHAN_TIMEOUT_MINUTES).minutes
    rescue StandardError
      DEFAULT_ORPHAN_TIMEOUT_MINUTES.minutes
    end

    def self.active_running_run_for(target_date)
      repair_orphan_runs!(target_date:)
      AicooDailyRun.running.where(target_date:).detect { |run| !orphan?(run) }
    end

    def self.repair_orphan_runs!(target_date: nil, apply: true)
      scope = AicooDailyRun.running.where(finished_at: nil)
      scope = scope.where(target_date:) if target_date
      guard = new(threshold: orphan_threshold)
      checked_count = 0
      repaired_count = 0

      scope.find_each do |run|
        checked_count += 1
        next unless guard.send(:orphan_run?, run)

        repaired_count += 1
        guard.send(:handle_stale_run!, run) if apply
      end

      Result.new(
        checked_count:,
        stuck_count: guard.instance_variable_get(:@stuck_count),
        partial_failed_count: guard.instance_variable_get(:@partial_failed_count)
      )
    end

    def self.diagnose_orphans(limit: nil)
      scope = AicooDailyRun.running.where(finished_at: nil).order(started_at: :asc, created_at: :asc)
      scope = scope.limit(limit) if limit
      guard = new(threshold: orphan_threshold)
      scope.map { |run| guard.send(:orphan_row, run) }
    end

    def self.orphan?(run)
      new(threshold: orphan_threshold).send(:orphan_run?, run)
    end

    def initialize(threshold:)
      @threshold = threshold
      @stuck_count = 0
      @partial_failed_count = 0
    end

    def call
      stale_runs = stale_running_runs
      checked_count = stale_runs.size
      stale_runs.each do |run|
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
      @stale_running_runs ||= AicooDailyRun.running.where(finished_at: nil).select { |run| orphan_run?(run) }
    end

    def handle_stale_run!(run)
      running_step = run.aicoo_daily_run_steps.where(status: "running").recent.first
      if running_step && previous_stuck_count_for(running_step.step_name, run.target_date) >= (MAX_STUCK_PER_STEP - 1)
        mark_step_failed!(run, running_step)
      else
        mark_run_stuck!(run, running_step)
      end
    end

    def orphan_run?(run)
      return false unless run&.running?

      last_activity_at(run) < threshold.ago
    end

    def orphan_row(run)
      running_step = run.aicoo_daily_run_steps.where(status: "running").recent.first
      last_updated_at = last_activity_at(run)
      OrphanRow.new(
        run:,
        step: running_step,
        last_heartbeat_at: heartbeat_at(running_step),
        last_updated_at:,
        stale_minutes: ((Time.current - last_updated_at) / 60).floor,
        orphan: orphan_run?(run)
      )
    end

    def last_activity_at(run)
      running_step = run.aicoo_daily_run_steps.where(status: "running").recent.first
      [
        heartbeat_at(running_step),
        running_step&.updated_at,
        run.updated_at,
        run.started_at,
        run.created_at
      ].compact.max || Time.at(0)
    end

    def heartbeat_at(step)
      return unless step

      value = step.metadata.to_h["heartbeat"] ||
        step.metadata.to_h.dig("last_progress", "at") ||
        step.metadata.to_h.dig("last_memory_event", "at")
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def previous_stuck_count_for(step_name, target_date)
      AicooDailyRunStep
        .joins(:aicoo_daily_run)
        .where(step_name:, status: "failed", aicoo_daily_runs: { target_date: })
        .where(aicoo_daily_runs: { status: %w[stuck partial_failed] })
        .where("aicoo_daily_run_steps.metadata -> 'stuck_guard' ->> 'reason' = ?", "orphan_running_run")
        .distinct
        .count(:aicoo_daily_run_id)
    end

    def mark_step_failed!(run, step)
      finished_at = Time.current
      message = "同じStep(#{step.step_name})で#{MAX_STUCK_PER_STEP}回以上stuckしたため、このStepだけfailedにしました。"
      fail_running_step!(step, finished_at:, message:, reason: "same_step_stuck_limit_reached")
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
        "プロセスの更新が#{threshold_minutes}分以上停止したため、孤児Runとして終了しました。last_step=#{step.step_name}"
      else
        "プロセスの更新が#{threshold_minutes}分以上停止したため、孤児Runとして終了しました。running stepなし"
      end
      fail_running_step!(step, finished_at:, message:, reason: "orphan_running_run") if step
      run.update!(
        status: "stuck",
        finished_at:,
        error_message: message,
        run_log: append_log(run.run_log, message)
      )
      @stuck_count += 1
    end

    def fail_running_step!(step, finished_at:, message:, reason:)
      step.update!(
        status: "failed",
        finished_at:,
        duration_seconds: duration_seconds(step.started_at, finished_at),
        error_message: message,
        metadata: step.metadata.to_h.merge(
          "orphaned" => true,
          "stuck_guard" => {
            "reason" => reason,
            "orphaned" => true,
            "timeout_minutes" => threshold_minutes,
            "marked_at" => finished_at.iso8601
          }
        )
      )
    end

    def threshold_minutes
      (threshold / 60).to_i
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

module Aicoo
  class DailyRunRetryDiagnostic
    Row = Data.define(
      :latest_run,
      :target_date,
      :retry_count,
      :retry_limit,
      :retry_limit_reached,
      :blocking_step,
      :blocking_reason,
      :blocked_since,
      :active_running_run,
      :manual_run_allowed,
      :cron_run_allowed,
      :recoverable_steps,
      :steps,
      :next_action
    )

    StepRow = Data.define(
      :step,
      :step_name,
      :status,
      :retry_count,
      :retry_limit,
      :recoverable,
      :last_error,
      :started_at,
      :finished_at,
      :next_action
    )

    def self.call(target_date: nil)
      new(target_date:).call
    end

    def initialize(target_date: nil)
      @target_date = target_date || AicooDailyRunSetting.current.target_date
    end

    def call
      Row.new(
        latest_run:,
        target_date:,
        retry_count:,
        retry_limit: setting.max_retry_per_day,
        retry_limit_reached: retry_limit_reached?,
        blocking_step:,
        blocking_reason:,
        blocked_since: blocking_step&.finished_at || blocking_step&.updated_at,
        active_running_run:,
        manual_run_allowed: manual_run_allowed?,
        cron_run_allowed: cron_run_allowed?,
        recoverable_steps: recoverable_steps,
        steps: step_rows,
        next_action:
      )
    end

    private

    attr_reader :target_date

    def setting
      @setting ||= AicooDailyRunSetting.current
    end

    def latest_run
      @latest_run ||= AicooDailyRun.where(target_date:).actual_runs.recent.first
    end

    def active_running_run
      @active_running_run ||= Aicoo::DailyRunStuckGuard.active_running_run_for(target_date)
    end

    def retry_count
      @retry_count ||= AicooDailyRun.where(target_date:).where.not(status: %w[skipped duplicate_skipped]).count
    end

    def retry_limit_reached?
      return retry_count.positive? unless setting.retry_until_success?

      retry_count >= setting.max_retry_per_day
    end

    def failed_step_counts
      @failed_step_counts ||= AicooDailyRunStep
        .joins(:aicoo_daily_run)
        .where(status: "failed", aicoo_daily_runs: { target_date:, source: "cron", status: %w[failed partial_failed stuck] })
        .group(:step_name)
        .count
    end

    def blocking_step_name
      failed_step_counts.find { |_step_name, count| count >= AicooDailyRunScheduler::MAX_FAILED_RETRIES_PER_STEP }&.first
    end

    def blocking_step
      return unless latest_run

      if blocking_step_name.present?
        latest_run.aicoo_daily_run_steps.where(step_name: blocking_step_name).recent.first
      else
        latest_run.current_step
      end
    end

    def blocking_reason
      return "active_running_run" if active_running_run
      return "step_retry_limit_reached" if blocking_step_name.present?
      return "retry_limit_reached" if retry_limit_reached?

      nil
    end

    def cron_run_allowed?
      active_running_run.nil? && blocking_step_name.blank? && !retry_limit_reached?
    end

    def manual_run_allowed?
      active_running_run.nil? && recoverable_steps.any?
    end

    def recoverable_steps
      @recoverable_steps ||= begin
        rows = latest_run ? latest_run.aicoo_daily_run_steps.select(&:recovery_needed?) : []
        if rows.blank? && latest_run && !latest_run.aicoo_daily_run_steps.where(step_name: Aicoo::ArticleOpportunityDailyRun::STEP_NAME, status: "success").exists?
          rows = [ latest_run.aicoo_daily_run_steps.where(step_name: Aicoo::ArticleOpportunityDailyRun::STEP_NAME).recent.first ].compact
          rows = [ latest_run.aicoo_daily_run_steps.build(step_name: Aicoo::ArticleOpportunityDailyRun::STEP_NAME, status: "skipped") ] if rows.blank?
        end
        rows.select { |step| AicooDailyRunStep::RECOVERABLE_STEP_NAMES.include?(step.step_name) }
      end
    end

    def step_rows
      return [] unless latest_run

      latest_run.aicoo_daily_run_steps.order(:created_at).map do |step|
        StepRow.new(
          step:,
          step_name: step.step_name,
          status: step.status,
          retry_count: step.recovery_attempt_count,
          retry_limit: AicooDailyRunStep::MAX_RECOVERY_ATTEMPTS,
          recoverable: step.recoverable?,
          last_error: step.error_message.presence || step.last_recovery_message,
          started_at: step.started_at,
          finished_at: step.finished_at,
          next_action: step_next_action(step)
        )
      end
    end

    def step_next_action(step)
      return "manual_recovery_available" if step.recovery_available?
      return "not_recoverable" unless step.recoverable?

      step.recovery_unavailable_reason.presence || "no_action"
    end

    def next_action
      return "同じ対象日のDaily Runが現在実行中です" if active_running_run
      return "APPLY=1 bin/rails aicoo:daily_run_manual TARGET_STEP=#{recoverable_steps.first.step_name}" if manual_run_allowed?
      return "回復対象Stepがありません" unless latest_run

      "Cron再実行は停止中です。必要ならTARGET_STEPを指定して手動診断してください"
    end
  end
end

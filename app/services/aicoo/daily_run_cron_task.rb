module Aicoo
  class DailyRunCronTask
    ENABLED_ENV_KEY = "AICOO_DAILY_RUN_ENABLED"
    ENABLED_VALUE = "true"

    Result = Data.define(:status, :message, :daily_run)

    def self.call(scheduler: AicooDailyRunScheduler)
      new(scheduler:).call
    end

    def self.enabled?
      ENV.fetch(ENABLED_ENV_KEY, nil).to_s == ENABLED_VALUE
    end

    def initialize(scheduler:)
      @scheduler = scheduler
    end

    def call
      started_at = Time.current
      unless self.class.enabled?
        message = "AICOO Daily Run cron disabled: #{ENABLED_ENV_KEY} is not true."
        Rails.logger.info(message)
        return Result.new(status: "disabled", message:, daily_run: nil)
      end

      Rails.logger.info("AICOO Daily Run cron started.")
      daily_run = scheduler.check!(source: "cron")
      message = "AICOO Daily Run cron finished: daily_run_id=#{daily_run.id} status=#{daily_run.status} target_date=#{daily_run.target_date}"
      Rails.logger.info(message)
      Result.new(status: daily_run.status, message:, daily_run:)
    rescue StandardError => e
      Rails.logger.error("AICOO Daily Run cron failed: #{e.class}: #{e.message}")
      record_failure!(error: e, started_at:)
      raise
    end

    private

    attr_reader :scheduler

    def record_failure!(error:, started_at:)
      target_date = cron_target_date
      run = recent_cron_run_since(started_at:, target_date:) || create_failure_run(error:, started_at:, target_date:)
      mark_run_failed!(run:, error:)
      record_failure_step!(run:, error:, started_at:)
      Rails.logger.error(
        "AICOO Daily Run cron failure recorded: daily_run_id=#{run.id} " \
        "target_date=#{run.target_date} error=#{error.class}: #{error.message}"
      )
      run
    rescue StandardError => logging_error
      Rails.logger.error(
        "AICOO Daily Run cron failure logging failed: " \
        "#{logging_error.class}: #{logging_error.message}"
      )
      nil
    end

    def recent_cron_run_since(started_at:, target_date:)
      AicooDailyRun
        .where(source: "cron", target_date:)
        .where("created_at >= ?", started_at - 5.seconds)
        .order(created_at: :desc)
        .first
    end

    def create_failure_run(error:, started_at:, target_date:)
      finished_at = Time.current
      AicooDailyRun.create!(
        target_date:,
        status: "failed",
        source: "cron",
        retry_count: retry_count_for(target_date),
        started_at:,
        finished_at:,
        error_message: "#{error.class}: #{error.message}",
        run_log: "[#{finished_at.iso8601}] Cron boot failed: #{error.class}: #{error.message}"
      )
    end

    def mark_run_failed!(run:, error:)
      return if run.status.in?(%w[failed partial_failed stuck skipped])

      finished_at = Time.current
      run.update!(
        status: "failed",
        finished_at:,
        error_message: "#{error.class}: #{error.message}",
        run_log: [ run.run_log, "[#{finished_at.iso8601}] Cron execution failed: #{error.class}: #{error.message}" ].compact.join("\n")
      )
    end

    def record_failure_step!(run:, error:, started_at:)
      return if run.aicoo_daily_run_steps.where(step_name: "cron_execution", status: "failed").exists?

      finished_at = Time.current
      run.aicoo_daily_run_steps.create!(
        step_name: "cron_execution",
        status: "failed",
        started_at:,
        finished_at:,
        duration_seconds: finished_at - started_at,
        error_message: "#{error.class}: #{error.message}",
        metadata: {
          source: "render_cron",
          error_class: error.class.name,
          message: error.message,
          backtrace: error.backtrace.to_a.first(5)
        }
      )
    end

    def cron_target_date
      AicooDailyRunSetting.current.target_date
    rescue StandardError
      Time.zone.today - 1.day
    end

    def retry_count_for(target_date)
      AicooDailyRun.where(target_date:).where.not(status: "skipped").count
    end
  end
end

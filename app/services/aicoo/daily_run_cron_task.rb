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
      raise
    end

    private

    attr_reader :scheduler
  end
end

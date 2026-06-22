class AicooDailyRunScheduler
  STUCK_AFTER = 30.minutes

  Status = Data.define(
    :setting,
    :target_date,
    :next_run_at,
    :latest_run,
    :last_success_at,
    :retry_count,
    :max_retry_per_day,
    :last_error,
    :ready,
    :reason
  )

  def self.check!(source: "cron")
    new.check!(source:)
  end

  def self.catch_up_if_due!
    new.check!(source: "catch_up")
  end

  def self.status
    new.status
  end

  def initialize(setting: AicooDailyRunSetting.current)
    @setting = setting
  end

  def check!(source: "cron")
    setting.update!(last_checked_at: Time.current)
    mark_stuck_runs!
    return skipped("disabled", source:) unless setting.enabled?
    return skipped("not_due", source:) unless due?
    return skipped("already_success", source:) if successful_today?
    return running_run if running_run
    return skipped("retry_limit_reached", source:) if retry_limit_reached?

    AicooDailyRunner.run!(target_date:, source:)
  end

  def status
    mark_stuck_runs!
    Status.new(
      setting:,
      target_date:,
      next_run_at: next_run_at,
      latest_run:,
      last_success_at: setting.last_success_at || AicooDailyRun.successful.recent.first&.finished_at,
      retry_count: retry_count,
      max_retry_per_day: setting.max_retry_per_day,
      last_error: latest_run&.error_message,
      ready: due? && !successful_today? && !running_run && !retry_limit_reached?,
      reason: status_reason
    )
  end

  private

  attr_reader :setting

  def skipped(reason, source:)
    AicooDailyRun.create!(
      target_date:,
      status: "skipped",
      source:,
      retry_count: retry_count,
      started_at: Time.current,
      finished_at: Time.current,
      run_log: "Daily Run skipped: #{reason}"
    )
  end

  def due?
    Time.current >= scheduled_time
  end

  def scheduled_time
    setting.scheduled_time_for(Date.current)
  end

  def next_run_at
    due? ? setting.scheduled_time_for(Date.current + 1.day) : scheduled_time
  end

  def target_date
    Date.yesterday
  end

  def successful_today?
    AicooDailyRun.successful.where(target_date:).exists?
  end

  def running_run
    AicooDailyRun.running.find_by(target_date:)
  end

  def latest_run
    AicooDailyRun.recent.first
  end

  def retry_count
    AicooDailyRun.where(target_date:).where.not(status: "skipped").count
  end

  def retry_limit_reached?
    return retry_count.positive? unless setting.retry_until_success?

    retry_count >= setting.max_retry_per_day
  end

  def mark_stuck_runs!
    AicooDailyRun.running.where(finished_at: nil).where("started_at < ?", STUCK_AFTER.ago).find_each do |run|
      run.update!(
        status: "stuck",
        finished_at: Time.current,
        error_message: "runningのまま#{STUCK_AFTER.inspect}を超過しました"
      )
    end
  end

  def status_reason
    return "自動実行OFF" unless setting.enabled?
    return "実行時刻前" unless due?
    return "本日成功済み" if successful_today?
    return "実行中" if running_run
    return "最大再試行回数に到達" if retry_limit_reached?

    "実行可能"
  end
end

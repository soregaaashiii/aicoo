module Aicoo
  class DailyRunCronStatus
    Status = Data.define(
      :cron_enabled,
      :mode_label,
      :env_value,
      :scheduler_status,
      :latest_run,
      :last_run_at,
      :last_success_at,
      :today_success,
      :running_run,
      :running,
      :next_action
    )

    def call
      scheduler_status = AicooDailyRunScheduler.status
      latest_run = scheduler_status.latest_run || AicooDailyRun.recent.first
      running_run = AicooDailyRun.running.recent.first
      cron_enabled = Aicoo::DailyRunCronTask.enabled?

      Status.new(
        cron_enabled:,
        mode_label: cron_enabled ? "Cron Ready" : "Manual",
        env_value: ENV.fetch(Aicoo::DailyRunCronTask::ENABLED_ENV_KEY, nil).presence || "unset",
        scheduler_status:,
        latest_run:,
        last_run_at: latest_run&.started_at,
        last_success_at: scheduler_status.last_success_at,
        today_success: AicooDailyRun.successful.where(target_date: scheduler_status.target_date).exists?,
        running_run:,
        running: running_run.present?,
        next_action: next_action(cron_enabled)
      )
    end

    private

    def next_action(cron_enabled)
      if cron_enabled
        "Render Cron Jobを設定済みなら、CronからDaily Runを安全に起動できます。"
      else
        "無料版は手動実行のまま利用できます。有料化後にRender Cron JobとENVを設定してください。"
      end
    end
  end
end

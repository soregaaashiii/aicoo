module Admin
  class AicooDailyRunHealthController < ApplicationController
    def show
      @cron_health = Aicoo::CronHealthDashboard.new.call
      @cron_status = Aicoo::DailyRunCronStatus.new.call
      @scheduler_status = @cron_status.scheduler_status
      @recent_daily_runs = @cron_health.history_runs
    end
  end
end

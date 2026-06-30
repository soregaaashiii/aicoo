module Admin
  class AicooDailyRunHealthController < ApplicationController
    def show
      @cron_status = Aicoo::DailyRunCronStatus.new.call
      @scheduler_status = @cron_status.scheduler_status
      @recent_daily_runs = AicooDailyRun.recent.limit(10)
    end
  end
end

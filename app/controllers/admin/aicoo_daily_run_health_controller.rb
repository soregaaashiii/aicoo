module Admin
  class AicooDailyRunHealthController < ApplicationController
    def show
      @cron_health = Aicoo::CronHealthDashboard.new.call
      @cron_status = Aicoo::DailyRunCronStatus.new.call
      @scheduler_status = @cron_status.scheduler_status
      @recent_daily_runs = @cron_health.history_runs
      @google_credential = AicooGoogleCredential.default
      @google_oauth_recovery_statuses = Aicoo::GoogleOauthRecoveryStatus.new(credential: @google_credential).call
    end
  end
end

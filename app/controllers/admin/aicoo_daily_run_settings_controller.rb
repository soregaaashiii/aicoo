module Admin
  class AicooDailyRunSettingsController < ApplicationController
    def show
      @setting = AicooDailyRunSetting.current
      @scheduler_status = AicooDailyRunScheduler.status
    end

    def update
      @setting = AicooDailyRunSetting.current

      if @setting.update(setting_params)
        redirect_to admin_aicoo_daily_run_settings_path, notice: "Daily Run設定を保存しました。"
      else
        @scheduler_status = AicooDailyRunScheduler.status
        render :show, status: :unprocessable_entity
      end
    end

    private

    def setting_params
      params.expect(
        aicoo_daily_run_setting: [
          :enabled,
          :run_hour,
          :run_minute,
          :timezone,
          :catch_up_enabled,
          :retry_until_success,
          :max_retry_per_day
        ]
      )
    end
  end
end

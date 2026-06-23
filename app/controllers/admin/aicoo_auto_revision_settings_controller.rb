module Admin
  class AicooAutoRevisionSettingsController < ApplicationController
    def show
      @setting = AicooAutoRevisionSetting.current
      @latest_queue_run = AutoRevisionQueueRun.recent.first
    end

    def update
      @setting = AicooAutoRevisionSetting.current
      if @setting.update(setting_params)
        redirect_to admin_aicoo_auto_revision_settings_path, notice: "Auto Revision自動キュー設定を保存しました。"
      else
        @latest_queue_run = AutoRevisionQueueRun.recent.first
        flash.now[:alert] = @setting.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    private

    def setting_params
      params.expect(
        aicoo_auto_revision_setting: [
          :enabled,
          :max_tasks_per_run,
          :minimum_final_score,
          :allow_medium_risk
        ]
      )
    end
  end
end

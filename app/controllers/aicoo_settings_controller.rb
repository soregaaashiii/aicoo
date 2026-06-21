class AicooSettingsController < ApplicationController
  def show
    @aicoo_setting = AicooSetting.current
  end

  def update
    @aicoo_setting = AicooSetting.current

    if @aicoo_setting.update(aicoo_setting_params)
      redirect_to aicoo_setting_path, notice: "AICOO設定を保存しました。"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def aicoo_setting_params
    params.expect(aicoo_setting: [ :auto_queue_data_preparation_tasks ])
  end
end

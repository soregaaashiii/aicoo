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
    params.expect(aicoo_setting: [
      :auto_queue_data_preparation_tasks,
      :daily_owner_queue_limit,
      :auto_queue_low_risk_enabled,
      :auto_queue_medium_risk_enabled,
      :auto_queue_high_risk_enabled,
      :long_term_profit_weight,
      :short_term_profit_weight,
      :learning_weight,
      :automation_weight,
      :exploration_weight,
      :strategic_learning_enabled,
      :strategic_learning_max_boost_rate,
      :strategic_learning_max_penalty_rate,
      :strategic_learning_warning_threshold_rate,
      :strategic_learning_decision_log_min_count
    ])
  end
end

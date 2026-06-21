class AicooDailyRunsController < ApplicationController
  def index
    @daily_runs = AicooDailyRun.recent.limit(50)
  end

  def show
    @daily_run = AicooDailyRun.find(params[:id])
    @correction_readiness = AicooCorrectionReadinessService.new.call
  end

  def create
    target_date = daily_run_target_date
    daily_run = AicooDailyRunner.run!(target_date:)

    if daily_run.running?
      redirect_to daily_run, alert: "#{target_date} のDaily Runはすでに実行中です。"
    else
      redirect_to daily_run, notice: "#{target_date} のAICOO Daily Runを実行しました。"
    end
  rescue Date::Error => e
    redirect_back fallback_location: aicoo_daily_runs_path, alert: "AICOO Daily Runの対象日が不正です: #{e.message}"
  rescue StandardError => e
    redirect_back fallback_location: aicoo_daily_runs_path, alert: "AICOO Daily Runに失敗しました: #{e.message}"
  end

  private

  def daily_run_target_date
    value = params.dig(:aicoo_daily_run, :target_date).presence || params[:target_date].presence
    value.present? ? Date.parse(value) : Date.yesterday
  end
end

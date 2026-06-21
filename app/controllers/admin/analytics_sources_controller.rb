module Admin
  class AnalyticsSourcesController < ApplicationController
    before_action :set_setting, only: %i[edit update destroy fetch_now]

    def index
      @settings = AnalyticsSourceSetting.recent
      @fetch_runs = AnalyticsFetchRun.includes(:analytics_source_setting).recent.limit(20)
      @readiness = AicooAnalytics::ScheduleReadinessChecker.new.call
    end

    def new
      @setting = AnalyticsSourceSetting.new(source_type: params[:source_type].presence_in(AnalyticsSourceSetting::SOURCE_TYPES) || "gsc")
    end

    def create
      @setting = AnalyticsSourceSetting.new(setting_params)

      if @setting.save
        redirect_to admin_analytics_sources_path, notice: "上級者向け設定を作成しました"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @setting.update(setting_params_for_update)
        redirect_to admin_analytics_sources_path, notice: "上級者向け設定を更新しました"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @setting.destroy!
      redirect_to admin_analytics_sources_path, notice: "上級者向け設定を削除しました"
    end

    def fetch_now
      run = AicooAnalytics::FetchRunner.new(@setting).call
      if run.status == "success"
        redirect_to admin_analytics_sources_path,
                    notice: "#{@setting.source_type.upcase}を取得しました。DataImport #{run.data_import_id}、Snapshot #{run.snapshot_count}件作成しました。"
      else
        redirect_to admin_analytics_sources_path, alert: "分析データ取得に失敗しました: #{run.error_message}"
      end
    end

    def fetch_all
      AnalyticsSourceSetting.where(enabled: true).find_each do |setting|
        AicooAnalytics::FetchRunner.new(setting).call
      end
      redirect_to admin_analytics_sources_path,
                  notice: "全有効設定の取得を実行しました。"
    end

    def check_readiness
      redirect_to admin_analytics_sources_path(anchor: "schedule-readiness"), notice: "定期取得準備チェックを再実行しました"
    end

    private

    def set_setting
      @setting = AnalyticsSourceSetting.find(params.expect(:id))
    end

    def setting_params
      params.expect(
        analytics_source_setting: [
          :source_type,
          :name,
          :property_id,
          :site_url,
          :enabled,
          :client_id,
          :client_secret,
          :credentials_json,
          :refresh_token,
          :fetch_days
        ]
      )
    end

    def setting_params_for_update
      setting_params.tap do |permitted|
        permitted.delete(:credentials_json) if permitted[:credentials_json].blank?
        permitted.delete(:refresh_token) if permitted[:refresh_token].blank?
        permitted.delete(:client_id) if permitted[:client_id].blank?
        permitted.delete(:client_secret) if permitted[:client_secret].blank?
      end
    end
  end
end

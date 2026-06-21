module Admin
  class AnalyticsSitesController < ApplicationController
    before_action :set_site, only: %i[edit update fetch_gsc fetch_ga4 fetch_all]

    def index
      @sites = AicooAnalyticsSite.recent
    end

    def new
      @site = AicooAnalyticsSite.new(enabled: true)
    end

    def create
      @site = AicooAnalyticsSite.new(site_params)
      if @site.save
        redirect_to admin_analytics_sites_path, notice: "サイト別分析設定を作成しました"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @site.update(site_params)
        redirect_to admin_analytics_sites_path, notice: "サイト別分析設定を更新しました"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def fetch_gsc
      fetch_one(@site.gsc_setting, "GSC")
    end

    def fetch_ga4
      fetch_one(@site.ga4_setting, "GA4")
    end

    def fetch_all
      results = []
      {
        "GSC" => @site.gsc_setting,
        "GA4" => @site.ga4_setting
      }.each do |label, setting|
        if setting&.enabled?
          results << fetch_result(setting, label)
        else
          results << "#{label}は未設定のためスキップしました。"
        end
      end
      redirect_to admin_analytics_sites_path, notice: results.join(" ")
    end

    private

    def set_site
      @site = AicooAnalyticsSite.find(params.expect(:id))
    end

    def site_params
      params.expect(
        aicoo_analytics_site: [
          :name,
          :business_id,
          :public_url,
          :domain,
          :gsc_site_url,
          :ga4_property_id,
          :enabled,
          :notes
        ]
      )
    end

    def fetch_one(setting, label)
      unless setting&.enabled?
        redirect_to admin_analytics_sites_path, alert: "#{@site.name} の#{label}設定がありません"
        return
      end

      result = fetch_result(setting, label)
      redirect_to admin_analytics_sites_path, notice: result
    end

    def fetch_result(setting, label)
      run = AicooAnalytics::FetchRunner.new(setting).call
      if run.status == "success"
        "#{label}取得成功。"
      else
        "#{label}取得失敗。#{run.error_message}"
      end
    end
  end
end

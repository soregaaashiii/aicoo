module Admin
  class SerpSettingsController < ApplicationController
    def show
      load_settings
    end

    def update
      load_settings
      @serp_profile.update!(
        monthly_budget_yen: serp_settings_params[:monthly_budget_yen].to_i,
        monthly_spend_yen: serp_settings_params[:monthly_spend_yen].to_i,
        metadata: @serp_profile.metadata.to_h.merge(
          Aicoo::Serp::ScanPlan::METADATA_UNIT_COST_KEY => serp_settings_params[:unit_result_cost_yen].presence || Aicoo::Serp::ScanPlan::DEFAULT_UNIT_RESULT_COST_YEN
        )
      )
      redirect_to admin_serp_settings_path, notice: "SERP予算設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      load_settings
      flash.now[:alert] = "SERP予算設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
      render :show, status: :unprocessable_entity
    end

    def test_search
      load_settings
      @test_params = test_search_params.to_h.symbolize_keys
      @result = Aicoo::Serp::Adapter.call(
        provider: @test_params[:provider].presence&.to_sym,
        type: @test_params[:type].presence&.to_sym || :google_search,
        query: @test_params[:query],
        location: @test_params[:location].presence || "Japan",
        language: @test_params[:language].presence || "ja",
        limit: @test_params[:limit].presence || 10
      )
      flash.now[:notice] = "SERPテスト検索が完了しました。"
      render :show, status: :ok
    rescue Aicoo::Serp::MissingApiKeyError,
           Aicoo::Serp::UnsupportedProviderError,
           Aicoo::Serp::UnsupportedSearchTypeError,
           Aicoo::Serp::HttpError,
           Aicoo::Serp::RateLimitError,
           Aicoo::Serp::TimeoutError,
           Aicoo::Serp::ParseError => e
      load_settings
      @test_params ||= test_search_params.to_h.symbolize_keys
      @error_message = e.message
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end

    private

    def load_settings
      @provider_keys = Aicoo::Serp::ProviderRegistry.provider_keys
      @current_provider = (ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
      @serp_profile = DataSourceCostProfile.for_source("serp")
      @api_key_configured = ENV["SERPER_API_KEY"].present? || @serp_profile.api_key.present?
      @test_params ||= {
        provider: @current_provider,
        type: "google_search",
        query: "大阪 喫煙 カフェ",
        location: "Japan",
        language: "ja",
        limit: 10
      }
    end

    def test_search_params
      params.fetch(:serp_test, {}).permit(:provider, :type, :query, :location, :language, :limit)
    end

    def serp_settings_params
      params.fetch(:serp_settings, {}).permit(:monthly_budget_yen, :monthly_spend_yen, :unit_result_cost_yen)
    end
  end
end

class AicooSettingsController < ApplicationController
  def show
    @aicoo_setting = AicooSetting.current
    load_data_source_cost_context
  end

  def update
    @aicoo_setting = AicooSetting.current

    if @aicoo_setting.update(aicoo_setting_params)
      redirect_to aicoo_setting_path, notice: "AICOO設定を保存しました。"
    else
      load_data_source_cost_context
      render :show, status: :unprocessable_entity
    end
  end

  def update_data_sources
    DataSourceCostProfile.ensure_defaults!
    update_cost_profiles!
    update_business_data_source_settings!

    redirect_to aicoo_setting_path(anchor: "data-source-costs"), notice: "Data Source Cost設定を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    @aicoo_setting = AicooSetting.current
    load_data_source_cost_context
    flash.now[:alert] = "Data Source Cost設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    render :show, status: :unprocessable_entity
  end

  private

  def load_data_source_cost_context
    DataSourceCostProfile.ensure_defaults!
    @cost_summary = Aicoo::CostEngine.new(ensure_defaults: false).call
    @data_source_cost_profiles = @cost_summary.profiles
    @cost_estimates_by_source_key = @cost_summary.estimates.index_by(&:source_key)
    @businesses = Business.real_businesses.select(:id, :name).order(:name).load
    business_data_source_settings = BusinessDataSourceSetting
      .where(
        business_id: @businesses.map(&:id),
        source_key: @data_source_cost_profiles.map(&:source_key)
      )
      .select(:id, :business_id, :source_key, :enabled, :connection_status)
      .load
    @business_data_source_settings = business_data_source_settings.index_by { |setting| [ setting.business_id, setting.source_key ] }
    @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new(
      profiles: @data_source_cost_profiles,
      settings: business_data_source_settings
    )
    load_global_connections
  end

  def load_global_connections
    cloudflare_profile = DataSourceCostProfile.find_by(source_key: Aicoo::CloudflarePages::Configuration::PROFILE_KEY)
    cloudflare = Aicoo::CloudflarePages::Configuration.new(profile: cloudflare_profile)
    google = AicooGoogleCredential.default
    webhook = Aicoo::Lovable::GithubWebhookConfiguration.new
    github = Aicoo::CloudflarePages::Configuration.new
    github_connected = github.github_configured?
    cloudflare_status = cloudflare.connection_status
    google_connected = google&.connected?
    webhook_connected = webhook.configured?
    webhook_diagnostics = webhook.diagnostics
    @global_connections = [
      {
        key: "github",
        label: "GitHub",
        status: github_connected ? "接続済み" : "未接続",
        level: github_connected ? "healthy" : "attention",
        detail: github.repository_url,
        path: admin_lovable_path(anchor: "github-webhook-settings")
      },
      {
        key: "cloudflare",
        label: "Cloudflare",
        status: { "connected" => "接続済み", "error" => "接続エラー" }.fetch(cloudflare_status, "未接続"),
        level: cloudflare_status == "connected" ? "healthy" : (cloudflare_status == "error" ? "critical" : "attention"),
        detail: cloudflare.last_connected_at ? "最終接続 #{I18n.l(cloudflare.last_connected_at, format: :short)}" : "全体認証",
        path: admin_cloudflare_connection_path
      },
      {
        key: "ga4",
        label: "GA4",
        status: google_connected ? "接続済み" : "未接続",
        level: google_connected ? "healthy" : "attention",
        detail: "AICOO共通Google認証",
        path: admin_analytics_connections_path
      },
      {
        key: "gsc",
        label: "GSC",
        status: google_connected ? "接続済み" : "未接続",
        level: google_connected ? "healthy" : "attention",
        detail: "AICOO共通Google認証",
        path: admin_analytics_connections_path
      },
      {
        key: "webhook",
        label: "Webhook",
        status: webhook_connected ? "接続済み" : "未接続",
        level: webhook_connected ? "healthy" : "attention",
        detail: webhook_diagnostics["last_received_at"].presence || "Push event",
        path: admin_lovable_path(anchor: "github-webhook-settings")
      }
    ]
  end

  def update_cost_profiles!
    data_source_params.each do |source_key, attributes|
      profile = DataSourceCostProfile.find_or_initialize_by(source_key:)
      credentials = merge_credentials(profile, attributes[:credentials])
      profile.assign_attributes(
        name: attributes[:name],
        enabled: ActiveModel::Type::Boolean.new.cast(attributes[:enabled]),
        execution_mode: attributes[:execution_mode],
        api_key: attributes[:api_key].presence || profile.api_key,
        monthly_budget_yen: attributes[:monthly_budget_yen].to_i,
        monthly_spend_yen: attributes[:monthly_spend_yen].to_i,
        monthly_run_count: attributes[:monthly_run_count].to_i,
        average_cost_yen: attributes[:average_cost_yen].to_d,
        average_expected_profit_yen: attributes[:average_expected_profit_yen].to_d,
        metadata: profile.metadata.merge("credentials" => credentials)
      )
      profile.save!
    end
  end

  def update_business_data_source_settings!
    business_data_source_params.each do |business_id, settings|
      business = Business.find(business_id)
      settings.each do |source_key, attributes|
        setting = BusinessDataSourceSetting.find_or_initialize_by(business:, source_key:)
        setting.enabled = ActiveModel::Type::Boolean.new.cast(attributes[:enabled])
        setting.save!
      end
    end
  end

  def data_source_params
    params.fetch(:data_sources, {}).permit!.to_h
  end

  def merge_credentials(profile, raw_credentials)
    credentials = profile.credentials.dup
    raw_credentials.to_h.each do |key, value|
      next if value.blank? && profile.credential_configured?(key)

      if key.to_s == "api_key"
        profile.api_key = value.presence || profile.api_key
      else
        credentials[key.to_s] = value
      end
    end
    credentials
  end

  def business_data_source_params
    params.fetch(:business_data_sources, {}).permit!.to_h
  end

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

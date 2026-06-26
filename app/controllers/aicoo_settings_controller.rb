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
    @cost_summary = Aicoo::CostEngine.new.call
    @data_source_cost_profiles = @cost_summary.profiles
    @businesses = Business.order(:name)
    @business_data_source_settings = BusinessDataSourceSetting.all.index_by { |setting| [ setting.business_id, setting.source_key ] }
    @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new(
      profiles: @data_source_cost_profiles,
      settings: BusinessDataSourceSetting.all
    )
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

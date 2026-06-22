module Admin
  class AnalyticsConnectionsController < ApplicationController
    require "json"

    def index
      @connections = build_connections
      @business_name = params[:business_name]
      @gsc_site_url = params[:gsc_site_url]
      @ga4_property_id = params[:ga4_property_id]
      @enabled = params.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(params[:enabled]) : true
      @fetch_days = params[:fetch_days].presence || 28
      @google_auth_statuses = google_auth_statuses
      @google_oauth_status = google_oauth_status
    end

    def create
      result = save_connection

      if result[:errors].empty?
        flash[:alert] = result[:warnings].uniq.join(" / ") if result[:warnings].present?
        redirect_to admin_analytics_connections_path, notice: "分析設定を保存しました"
      else
        @connections = build_connections
        @business_name = connection_params[:business_name]
        @gsc_site_url = connection_params[:gsc_site_url]
        @ga4_property_id = connection_params[:ga4_property_id]
        @enabled = ActiveModel::Type::Boolean.new.cast(connection_params[:enabled])
        @fetch_days = connection_params[:fetch_days].presence || 28
        @google_auth_statuses = google_auth_statuses
        @google_oauth_status = google_oauth_status
        flash.now[:alert] = (result[:errors] + result[:warnings]).uniq.join(" / ")
        render :index, status: :unprocessable_content
      end
    end

    def fetch_gsc
      fetch_one("gsc", "GSC")
    end

    def fetch_ga4
      fetch_one("ga4", "GA4")
    end

    def fetch_all_for_business
      redirect_with_fetch_messages(fetch_many)
    end

    def delete_credentials_json
      settings = business_settings(connection_business_name)
      updated_count = 0

      settings.each do |setting|
        next if setting.credentials_json.blank?

        setting.update!(credentials_json: nil)
        updated_count += 1
      end

      redirect_to admin_analytics_connections_path,
                  notice: "認証JSONを#{updated_count}件削除しました。client_id / client_secret / refresh_token は保持しました。"
    end

    private

    def build_connections
      settings_by_business = AnalyticsSourceSetting.order(:name, created_at: :desc).group_by do |setting|
        business_name_for(setting.name)
      end

      settings_by_business.map do |name, settings|
        AnalyticsConnection.new(
          business_name: name,
          gsc_setting: settings.find { |setting| setting.source_type == "gsc" },
          ga4_setting: settings.find { |setting| setting.source_type == "ga4" }
        )
      end.sort_by(&:business_name)
    end

    def setting_for(name, source_type)
      AnalyticsSourceSetting.where(source_type:).order(created_at: :desc).find do |setting|
        business_name_for(setting.name) == name
      end
    end

    def save_connection
      errors = []
      warnings = []
      business_name = clean_text(connection_params[:business_name])
      gsc_site_url = clean_text(connection_params[:gsc_site_url])
      ga4_property_id = clean_text(connection_params[:ga4_property_id])

      if business_name.blank?
        errors << "事業名を入力してください"
        return { errors:, warnings: }
      end

      if gsc_site_url.blank? && ga4_property_id.blank?
        disable_blank_setting(business_name, "gsc", warnings)
        disable_blank_setting(business_name, "ga4", warnings)
        errors << "GSCまたはGA4のどちらかを設定してください"
        return { errors:, warnings: }
      end

      save_gsc_setting(business_name, errors)
      save_ga4_setting(business_name, errors)
      disable_blank_setting(business_name, "gsc", warnings) if gsc_site_url.blank?
      disable_blank_setting(business_name, "ga4", warnings) if ga4_property_id.blank?
      apply_credentials_to_business_settings(business_name, errors)
      warnings << "GA4が未設定です。GSCのみ取得できます。" if ga4_property_id.blank?
      warnings << "GSCが未設定です。GA4のみ取得できます。" if gsc_site_url.blank?
      { errors:, warnings: }
    end

    def save_gsc_setting(business_name, errors)
      site_url = clean_text(connection_params[:gsc_site_url])
      return if site_url.blank?

      setting = find_connection_setting("gsc", business_name, site_url)

      setting ||= AnalyticsSourceSetting.new(source_type: "gsc")
      setting.assign_attributes(
        name: source_setting_name(business_name, "GSC"),
        site_url:,
        enabled: connection_enabled?,
        fetch_days: connection_fetch_days,
        **credential_attributes_for(setting, business_name:)
      )
      errors.concat(setting.errors.full_messages) unless setting.save
    end

    def save_ga4_setting(business_name, errors)
      property_id = clean_text(connection_params[:ga4_property_id])
      return if property_id.blank?

      setting = find_connection_setting("ga4", business_name, property_id)

      setting ||= AnalyticsSourceSetting.new(source_type: "ga4")
      setting.assign_attributes(
        name: source_setting_name(business_name, "GA4"),
        property_id:,
        enabled: connection_enabled?,
        fetch_days: connection_fetch_days,
        **credential_attributes_for(setting, business_name:)
      )
      errors.concat(setting.errors.full_messages) unless setting.save
    end

    def apply_credentials_to_business_settings(business_name, errors)
      return unless credential_input_present?

      business_settings(business_name).each do |setting|
        setting.assign_attributes(credential_attributes_for(setting, business_name:))
        errors.concat(setting.errors.full_messages) unless setting.save
      end
    end

    def find_connection_setting(source_type, business_name, identifier)
      by_business = setting_for(business_name, source_type)
      return by_business if by_business

      case source_type
      when "gsc"
        identifier.present? ? AnalyticsSourceSetting.find_by(source_type:, site_url: identifier) : nil
      when "ga4"
        identifier.present? ? AnalyticsSourceSetting.find_by(source_type:, property_id: identifier) : nil
      end
    end

    def disable_blank_setting(business_name, source_type, warnings)
      setting = setting_for(business_name, source_type)
      return unless setting

      setting.update(enabled: false)
      warnings << "#{source_label(source_type)}が未設定です。#{other_source_label(source_type)}のみ取得できます。"
    end

    def fetch_one(source_type, label)
      setting = enabled_setting_for(connection_business_name, source_type)
      unless setting
        redirect_to admin_analytics_connections_path, alert: "#{connection_business_name} の#{label}が未設定です。"
        return
      end

      redirect_with_fetch_messages(fetch_setting(setting, label), missing_complement_messages(source_type))
    end

    def fetch_many
      results = []

      %w[gsc ga4].each do |source_type|
        label = source_label(source_type)
        setting = enabled_setting_for(connection_business_name, source_type)
        if setting
          results << fetch_setting(setting, label)
        else
          results << { status: :skipped, message: "#{label}は未設定のためスキップしました。" }
        end
      end

      results
    end

    def fetch_setting(setting, label)
      run = AicooAnalytics::FetchRunner.new(setting).call
      return { status: :success, message: "#{label}取得成功。" } if run.status == "success"

      { status: :failed, message: "#{label}取得失敗。#{run.error_message}" }
    end

    def redirect_with_fetch_messages(results, extra_alerts = [])
      results = results.is_a?(Hash) ? [ results ] : Array(results)
      notices = results.select { |result| result[:status] == :success }.pluck(:message)
      alerts = results.reject { |result| result[:status] == :success }.pluck(:message) + extra_alerts

      if notices.empty? && alerts.empty?
        alerts << "取得できる分析設定がありません"
      elsif notices.empty? && alerts.all? { |message| message.include?("未設定") || message.include?("スキップ") }
        alerts << "GSCまたはGA4のどちらかを設定してください" if results.none? { |result| result[:status] == :success }
      end

      flash[:notice] = notices.join(" ") if notices.present?
      flash[:alert] = alerts.join(" ") if alerts.present?
      redirect_to admin_analytics_connections_path
    end

    def settings_for_business
      AnalyticsSourceSetting.where(source_type: %w[gsc ga4], enabled: true).select do |setting|
        business_name_for(setting.name) == connection_business_name
      end
    end

    def business_settings(business_name)
      AnalyticsSourceSetting.where(source_type: %w[gsc ga4]).select do |setting|
        business_name_for(setting.name) == business_name
      end
    end

    def connection_business_name
      params.expect(:business_name)
    end

    def connection_params
      params.expect(
        analytics_connection: [
          :business_name,
          :gsc_site_url,
          :ga4_property_id,
          :enabled,
          :fetch_days,
          :google_client_id,
          :google_client_secret,
          :google_refresh_token,
          :credentials_json
        ]
      )
    end

    def business_name_for(name)
      name.to_s.strip.sub(/\s*(GSC|GA4)\z/i, "").strip
    end

    def source_setting_name(business_name, label)
      "#{business_name} #{label}"
    end

    def connection_enabled?
      ActiveModel::Type::Boolean.new.cast(connection_params[:enabled])
    end

    def connection_fetch_days
      connection_params[:fetch_days].presence || 28
    end

    def enabled_setting_for(business_name, source_type)
      setting = setting_for(business_name, source_type)
      return setting if setting&.enabled?

      nil
    end

    def missing_complement_messages(source_type)
      other_source_type = source_type == "gsc" ? "ga4" : "gsc"
      return [] if enabled_setting_for(connection_business_name, other_source_type)

      [ "#{other_source_label(source_type)}が未設定です。#{source_label(source_type)}のみ取得できます。" ]
    end

    def source_label(source_type)
      source_type == "gsc" ? "GSC" : "GA4"
    end

    def other_source_label(source_type)
      source_type == "gsc" ? "GA4" : "GSC"
    end

    def credential_input_present?
      %i[google_client_id google_client_secret google_refresh_token credentials_json].any? do |key|
        clean_credential_value(connection_params[key]).present?
      end
    end

    def credential_attributes_for(setting, business_name: nil)
      attributes = {}
      source_setting = credential_source_for(setting, business_name)

      attributes[:client_id] = source_setting.client_id if source_setting&.client_id.present?
      attributes[:client_secret] = source_setting.client_secret if source_setting&.client_secret.present?
      attributes[:refresh_token] = source_setting.refresh_token if source_setting&.refresh_token.present?

      if connection_params[:google_client_id].present?
        attributes[:client_id] = clean_credential_value(connection_params[:google_client_id])
      end

      if connection_params[:google_client_secret].present?
        attributes[:client_secret] = clean_credential_value(connection_params[:google_client_secret])
      end

      if connection_params[:google_refresh_token].present?
        attributes[:refresh_token] = clean_credential_value(connection_params[:google_refresh_token])
      end

      attributes[:credentials_json] = credential_json_attributes(source_setting, attributes) if credential_input_present?
      attributes
    end

    def credential_json_attributes(source_setting, attributes)
      credentials = parsed_credentials(source_setting&.credentials_json)
      credentials["client_id"] = attributes[:client_id] if attributes[:client_id].present?
      credentials["client_secret"] = attributes[:client_secret] if attributes[:client_secret].present?
      credentials["refresh_token"] = attributes[:refresh_token] if attributes[:refresh_token].present?
      credentials.merge!(parsed_credentials(connection_params[:credentials_json])) if connection_params[:credentials_json].present?
      credentials.present? ? JSON.generate(credentials) : nil
    end

    def credential_source_for(setting, business_name)
      return setting if saved_credentials_present?(setting)

      business_name.present? ? business_settings(business_name).find { |candidate| saved_credentials_present?(candidate) } : setting
    end

    def saved_credentials_present?(setting)
      setting.present? && (
        setting.client_id.present? ||
        setting.client_secret.present? ||
        setting.credentials_json.present? ||
        setting.refresh_token.present?
      )
    end

    def parsed_credentials(raw_json)
      JSON.parse(raw_json.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def clean_text(value)
      value.to_s.strip
    end

    def clean_credential_value(value)
      clean_text(value).sub(/\A["']+/, "").sub(/["']+\z/, "").strip
    end

    def google_auth_statuses
      {
        "GOOGLE_CLIENT_ID" => env_status("GOOGLE_CLIENT_ID"),
        "GOOGLE_CLIENT_SECRET" => env_status("GOOGLE_CLIENT_SECRET"),
        "GOOGLE_REFRESH_TOKEN" => env_status("GOOGLE_REFRESH_TOKEN")
      }
    end

    def google_oauth_status
      credential = AicooGoogleCredential.default
      {
        connected: credential&.connected? || false,
        latest_connected_at: credential&.connected_at
      }
    end

    def env_status(key)
      ENV[key].present? ? "設定済み" : "未設定"
    end

    AnalyticsConnection = Data.define(:business_name, :gsc_setting, :ga4_setting) do
      def credentials_status
        return "設定済み" if env_credentials_present? ||
                        AicooGoogleCredential.default.present? ||
                        [ gsc_setting, ga4_setting ].compact.any? { |setting| saved_credentials_present?(setting) }

        "未設定"
      end

      def client_id_status
        credential_status_for(:client_id, "GOOGLE_CLIENT_ID", "client_id")
      end

      def client_secret_status
        credential_status_for(:client_secret, "GOOGLE_CLIENT_SECRET", "client_secret")
      end

      def refresh_token_status
        credential_status_for(:refresh_token, "GOOGLE_REFRESH_TOKEN", "refresh_token")
      end

      def credentials_json_status
        [ gsc_setting, ga4_setting ].compact.any? { |setting| setting.credentials_json.present? } ? "設定済み" : "未設定"
      end

      def google_credential_label
        credential = [ gsc_setting, ga4_setting ].compact.map(&:effective_google_credential).compact.first ||
                     AicooGoogleCredential.default
        credential ? "共通Google認証" : "未設定"
      end

      def last_fetched_at
        [ gsc_setting&.last_fetched_at, ga4_setting&.last_fetched_at, latest_fetch_run&.finished_at ].compact.max
      end

      def oauth_connected_at
        [
          gsc_setting&.oauth_connected_at,
          ga4_setting&.oauth_connected_at,
          gsc_setting&.effective_google_credential&.connected_at,
          ga4_setting&.effective_google_credential&.connected_at,
          AicooGoogleCredential.default&.connected_at
        ].compact.max
      end

      def latest_fetch_status
        latest_fetch_run&.status || "-"
      end

      def gsc_status
        source_status(gsc_setting, "site_url")
      end

      def ga4_status
        source_status(ga4_setting, "property_id")
      end

      def warnings
        [
          ("GSCが未設定です。GA4のみ取得できます。" if gsc_status == "未設定"),
          ("GA4が未設定です。GSCのみ取得できます。" if ga4_status == "未設定"),
          ("Google認証情報が未設定です。ENVまたは画面から設定してください。" if credentials_status == "未設定"),
          ("GSCの最終取得が失敗しています。" if gsc_status == "最終取得失敗"),
          ("GA4の最終取得が失敗しています。" if ga4_status == "最終取得失敗")
        ].compact
      end

      def enabled?
        [ gsc_setting, ga4_setting ].compact.any?(&:enabled?)
      end

      def fetch_days
        gsc_setting&.fetch_days || ga4_setting&.fetch_days || 28
      end

      private

      def latest_fetch_run
        AnalyticsFetchRun.where(analytics_source_setting: [ gsc_setting, ga4_setting ].compact).recent.first
      end

      def source_status(setting, identifier)
        return "未設定" unless setting&.enabled? && setting.public_send(identifier).present?

        case setting.latest_fetch_run&.status
        when "success"
          "最終取得成功"
        when "failed"
          "最終取得失敗"
        else
          "設定済み"
        end
      end

      def env_credentials_present?
        ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present? && ENV["GOOGLE_REFRESH_TOKEN"].present?
      end

      def saved_credentials_present?(setting)
        setting.client_id.present? ||
          setting.client_secret.present? ||
          setting.credentials_json.present? ||
          setting.refresh_token.present?
      end

      def credential_status_for(column_name, env_key, json_key)
        return "設定済み" if ENV[env_key].present?
        return "設定済み" if AicooGoogleCredential.default&.public_send(column_name).present?

        [ gsc_setting, ga4_setting ].compact.any? do |setting|
          setting.public_send(column_name).present? ||
            setting.effective_google_credential&.public_send(column_name).present? ||
            parsed_credentials(setting)[json_key].present?
        end ? "設定済み" : "未設定"
      end

      def parsed_credentials(setting)
        JSON.parse(setting.credentials_json.presence || "{}")
      rescue JSON::ParserError
        {}
      end
    end
  end
end

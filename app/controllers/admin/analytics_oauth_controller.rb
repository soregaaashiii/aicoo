module Admin
  class AnalyticsOauthController < ApplicationController
    def connect
      credentials = oauth_credentials(target_settings)

      if credentials[:client_id].blank? || credentials[:client_secret].blank?
        redirect_to admin_analytics_connections_path, alert: "Google OAuth Client ID / Secret が未設定です。ENVまたは分析設定画面から保存してください。"
        return
      end

      redirect_to AicooAnalytics::GoogleOauthAuthorization.authorization_uri(
        client_id: credentials[:client_id],
        redirect_uri: admin_analytics_oauth_callback_url,
        state: params[:business_name].presence
      ).to_s, allow_other_host: true
    end

    def callback
      if params[:error].present?
        redirect_to admin_analytics_connections_path, alert: "Google OAuth認証に失敗しました: #{params[:error]} #{params[:error_description]}"
        return
      end

      if params[:code].blank?
        redirect_to admin_analytics_connections_path, alert: "Google OAuth認証に失敗しました: code が返りませんでした。"
        return
      end

      settings = target_settings(params[:state].presence)
      if settings.empty?
        redirect_to admin_analytics_connections_path, alert: "refresh_tokenを保存する分析設定がありません。先にGSCまたはGA4を設定してください。"
        return
      end

      credentials = oauth_credentials(settings)
      token_response = AicooAnalytics::GoogleOauthAuthorization.exchange_code(
        code: params[:code],
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        redirect_uri: admin_analytics_oauth_callback_url
      )

      if token_response.refresh_token.blank?
        redirect_to admin_analytics_connections_path,
                    alert: "Google OAuth認証は完了しましたがrefresh_tokenが返りませんでした。再度「Googleと接続」を押してください。"
        return
      end

      save_oauth_credentials!(settings, credentials, token_response.refresh_token)
      redirect_to admin_analytics_connections_path, notice: "Google OAuth接続が完了しました。GSC/GA4のrefresh_tokenを保存しました。"
    rescue AicooAnalytics::GoogleOauthAuthorization::Error => e
      redirect_to admin_analytics_connections_path, alert: "Google OAuth認証に失敗しました: #{e.message}"
    end

    private

    def target_settings(business_name = params[:business_name].presence)
      scope = AnalyticsSourceSetting.where(source_type: %w[gsc ga4])
      return scope.to_a if business_name.blank?

      scope.select { |setting| business_name_for(setting.name) == business_name }
    end

    def oauth_credentials(settings)
      source = settings.find { |setting| setting.client_id.present? && setting.client_secret.present? }
      {
        client_id: source&.client_id.presence || ENV["GOOGLE_CLIENT_ID"],
        client_secret: source&.client_secret.presence || ENV["GOOGLE_CLIENT_SECRET"]
      }
    end

    def save_oauth_credentials!(settings, credentials, refresh_token)
      now = Time.current
      settings.each do |setting|
        setting.update!(
          client_id: credentials[:client_id],
          client_secret: credentials[:client_secret],
          refresh_token:,
          oauth_connected_at: now
        )
      end
    end

    def business_name_for(name)
      name.to_s.strip.sub(/\s*(GSC|GA4)\z/i, "").strip
    end
  end
end

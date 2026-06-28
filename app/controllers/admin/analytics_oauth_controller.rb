module Admin
  class AnalyticsOauthController < ApplicationController
    def connect
      credential = target_google_credential
      credentials = oauth_credentials(credential)

      if credentials[:client_id].blank? || credentials[:client_secret].blank?
        redirect_to admin_analytics_connections_path, alert: "Google OAuth Client ID / Secret が未設定です。ENVまたは分析設定画面から保存してください。"
        return
      end

      remember_oauth_credentials!(credentials, params[:business_name].presence, credential)
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
      google_credential = target_google_credential_from_session
      credentials = oauth_credentials(google_credential)
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

      save_oauth_credentials!(settings, google_credential, credentials, token_response)
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

    def target_google_credential
      if params[:google_credential_id].present?
        AicooGoogleCredential.find(params[:google_credential_id])
      else
        AicooGoogleCredential.default || AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
      end
    end

    def target_google_credential_from_session
      if session[:analytics_oauth_google_credential_id].present?
        AicooGoogleCredential.find_by(id: session[:analytics_oauth_google_credential_id]) ||
          AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
      else
        AicooGoogleCredential.default || AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
      end
    end

    def oauth_credentials(credential)
      return session_oauth_credentials if session_oauth_credentials.present?

      {
        client_id: ENV["GOOGLE_CLIENT_ID"].presence || credential.client_id,
        client_secret: ENV["GOOGLE_CLIENT_SECRET"].presence || credential.client_secret
      }
    end

    def save_oauth_credentials!(settings, google_credential, credentials, token_response)
      now = Time.current
      google_credential.assign_attributes(
        name: google_credential.name.presence || "AICOO共通Google認証",
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        refresh_token: token_response.refresh_token,
        access_token: token_response.access_token,
        token_expires_at: token_response.token_expires_at,
        google_account_email: token_response.account_email,
        enabled: true,
        connected_at: now
      )
      google_credential.save!

      settings.each do |setting|
        setting.update!(
          google_credential:,
          client_id: nil,
          client_secret: nil,
          refresh_token: nil,
          credentials_json: nil,
          oauth_connected_at: now
        )
      end
      clear_remembered_oauth_credentials!
    end

    def remember_oauth_credentials!(credentials, business_name, google_credential)
      session[:analytics_oauth_client_id] = credentials[:client_id]
      session[:analytics_oauth_client_secret] = credentials[:client_secret]
      session[:analytics_oauth_business_name] = business_name
      session[:analytics_oauth_google_credential_id] = google_credential.id if google_credential.persisted?
    end

    def session_oauth_credentials
      return nil if session[:analytics_oauth_client_id].blank? || session[:analytics_oauth_client_secret].blank?

      {
        client_id: session[:analytics_oauth_client_id],
        client_secret: session[:analytics_oauth_client_secret]
      }
    end

    def clear_remembered_oauth_credentials!
      session.delete(:analytics_oauth_client_id)
      session.delete(:analytics_oauth_client_secret)
      session.delete(:analytics_oauth_business_name)
      session.delete(:analytics_oauth_google_credential_id)
    end

    def business_name_for(name)
      name.to_s.strip.sub(/\s*(GSC|GA4)\z/i, "").strip
    end
  end
end

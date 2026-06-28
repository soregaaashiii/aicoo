module Admin
  class AnalyticsOauthController < ApplicationController
    def connect
      credential = target_google_credential
      credentials = oauth_credentials(credential)

      if credentials[:client_id].blank? || credentials[:client_secret].blank?
        redirect_to admin_google_credentials_path, alert: "Google OAuth Client ID / Secret が未設定です。Google認証画面から保存してください。"
        return
      end

      remember_oauth_credentials!(credentials, params[:business_name].presence, credential)
      log_oauth_start!(credential:, credentials:)
      redirect_to AicooAnalytics::GoogleOauthAuthorization.authorization_uri(
        client_id: credentials[:client_id],
        redirect_uri: admin_analytics_oauth_callback_url,
        state: params[:business_name].presence
      ).to_s, allow_other_host: true
    end

    def callback
      if params[:error].present?
        redirect_to admin_google_credentials_path, alert: oauth_callback_error_message(params[:error], params[:error_description])
        return
      end

      if params[:code].blank?
        redirect_to admin_google_credentials_path, alert: "Google OAuth認証に失敗しました: code が返りませんでした。"
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
        redirect_to admin_google_credentials_path,
                    alert: "Google OAuth認証は完了しましたがrefresh_tokenが返りませんでした。再度「Googleと接続」を押してください。"
        return
      end

      save_oauth_credentials!(settings, google_credential, credentials, token_response)
      redirect_to admin_google_credentials_path, notice: "Google OAuth接続が完了しました。Refresh Tokenを保存しました。"
    rescue AicooAnalytics::GoogleOauthAuthorization::Error => e
      redirect_to admin_google_credentials_path, alert: "Google OAuth認証に失敗しました: #{e.message}"
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

      if credential.client_id.present? && credential.client_secret.present?
        return {
          client_id: credential.client_id,
          client_secret: credential.client_secret,
          google_cloud_project_id: credential.google_cloud_project_id.presence
        }
      end

      if credential.persisted?
        return {
          client_id: credential.client_id.presence,
          client_secret: credential.client_secret.presence,
          google_cloud_project_id: credential.google_cloud_project_id.presence
        }
      end

      {
        client_id: ENV["GOOGLE_CLIENT_ID"].presence,
        client_secret: ENV["GOOGLE_CLIENT_SECRET"].presence,
        google_cloud_project_id: ENV["GOOGLE_CLOUD_PROJECT"].presence || ENV["GOOGLE_PROJECT_ID"].presence
      }
    end

    def save_oauth_credentials!(settings, google_credential, credentials, token_response)
      now = Time.current
      before_snapshot = google_credential.persisted? ? google_credential.reload : google_credential
      log_oauth_save_snapshot!("Before", before_snapshot)

      save_oauth_credential_record!(google_credential, credentials, token_response, now)

      google_credential.reload
      log_oauth_save_snapshot!("After", google_credential)
      verify_oauth_credentials_saved!(google_credential, credentials, token_response)

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

    def save_oauth_credential_record!(google_credential, credentials, token_response, now)
      if google_credential.persisted?
        google_credential.with_lock do
          assign_oauth_credential_attributes!(google_credential, credentials, token_response, now)
          google_credential.save!
        end
      else
        assign_oauth_credential_attributes!(google_credential, credentials, token_response, now)
        google_credential.save!
      end
    end

    def assign_oauth_credential_attributes!(google_credential, credentials, token_response, now)
      google_credential.assign_attributes(
        name: google_credential.name.presence || "AICOO共通Google認証",
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        google_cloud_project_id: credentials[:google_cloud_project_id].presence || google_credential.google_cloud_project_id,
        refresh_token: token_response.refresh_token,
        access_token: token_response.access_token,
        token_expires_at: token_response.token_expires_at,
        google_account_email: token_response.account_email,
        enabled: true,
        connected_at: now,
        last_oauth_success_at: now
      )
    end

    def remember_oauth_credentials!(credentials, business_name, google_credential)
      session[:analytics_oauth_client_id] = credentials[:client_id]
      session[:analytics_oauth_client_secret] = credentials[:client_secret]
      session[:analytics_oauth_google_cloud_project_id] = credentials[:google_cloud_project_id]
      session[:analytics_oauth_business_name] = business_name
      session[:analytics_oauth_google_credential_id] = google_credential.id if google_credential.persisted?
    end

    def session_oauth_credentials
      return nil if session[:analytics_oauth_client_id].blank? || session[:analytics_oauth_client_secret].blank?

      {
        client_id: session[:analytics_oauth_client_id],
        client_secret: session[:analytics_oauth_client_secret],
        google_cloud_project_id: session[:analytics_oauth_google_cloud_project_id]
      }
    end

    def clear_remembered_oauth_credentials!
      session.delete(:analytics_oauth_client_id)
      session.delete(:analytics_oauth_client_secret)
      session.delete(:analytics_oauth_google_cloud_project_id)
      session.delete(:analytics_oauth_business_name)
      session.delete(:analytics_oauth_google_credential_id)
    end

    def log_oauth_start!(credential:, credentials:)
      Rails.logger.info(
        [
          "Google OAuth start",
          "client_id=#{credentials[:client_id]}",
          "project_id=#{credentials[:google_cloud_project_id].presence || credential.effective_google_cloud_project_id.presence || 'unknown'}",
          "redirect_uri=#{admin_analytics_oauth_callback_url}",
          "scope=#{AicooAnalytics::GoogleOauthAuthorization::SCOPES.join(' ')}",
          "test_user_check=OAuth同意画面がテストモードの場合は利用するGoogleアカウントをテストユーザーに追加してください"
        ].join(" ")
      )
    end

    def log_oauth_save_snapshot!(label, credential)
      Rails.logger.info(
        [
          "Google OAuth credential #{label}",
          "client_id=#{credential.client_id.presence || 'blank'}",
          "project_id=#{credential.google_cloud_project_id.presence || credential.effective_google_cloud_project_id.presence || 'blank'}",
          "project_number=#{credential.oauth_project_number.presence || 'unknown'}",
          "refresh_token_present=#{credential.refresh_token.present?}",
          "last_oauth_success_at=#{credential.last_oauth_success_at || 'blank'}"
        ].join(" ")
      )
    end

    def verify_oauth_credentials_saved!(credential, credentials, token_response)
      checks = {
        client_id: credential.client_id == credentials[:client_id],
        client_secret: credential.client_secret == credentials[:client_secret],
        refresh_token: credential.refresh_token == token_response.refresh_token,
        access_token: credential.access_token == token_response.access_token,
        token_expires_at: credential.token_expires_at.present?,
        google_account_email: credential.google_account_email == token_response.account_email,
        last_oauth_success_at: credential.last_oauth_success_at.present?
      }
      if credentials[:google_cloud_project_id].present?
        checks[:google_cloud_project_id] = credential.google_cloud_project_id == credentials[:google_cloud_project_id]
      end
      failed_keys = checks.select { |_key, ok| !ok }.keys
      return if failed_keys.empty?

      raise AicooAnalytics::GoogleOauthAuthorization::Error,
            "Google OAuth認証情報をDBへ保存できませんでした: #{failed_keys.join(', ')}"
    end

    def oauth_callback_error_message(error, description)
      base = "Google認証に失敗しました。#{error} #{description}".strip
      return base unless error == "access_denied"

      [
        base,
        "原因候補:",
        "OAuth同意画面がテストモードで、現在のGoogleアカウントがテストユーザーに入っていません",
        "古いClient IDを使っています",
        "Redirect URIがGoogle Cloudに登録されていません",
        "確認してください:",
        "Google Cloud Project: aicoo-500805",
        "テストユーザー: abclologun@gmail.com",
        "Redirect URI: https://aicoo.onrender.com/admin/analytics_oauth/callback"
      ].join(" ")
    end

    def business_name_for(name)
      name.to_s.strip.sub(/\s*(GSC|GA4)\z/i, "").strip
    end
  end
end

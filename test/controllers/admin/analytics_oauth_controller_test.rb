require "test_helper"

module Admin
  class AnalyticsOauthControllerTest < ActionDispatch::IntegrationTest
    test "connect redirects to google oauth url with required options" do
      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret"
      ) do
        get admin_analytics_oauth_connect_url
      end

      assert_response :redirect
      uri = URI.parse(response.location)
      params = Rack::Utils.parse_nested_query(uri.query)
      scopes = params.fetch("scope").split

      assert_equal "accounts.google.com", uri.host
      assert_equal "env-client", params["client_id"]
      assert_equal admin_analytics_oauth_callback_url, params["redirect_uri"]
      assert_equal "code", params["response_type"]
      assert_equal "offline", params["access_type"]
      assert_equal "consent", params["prompt"]
      assert_includes scopes, "https://www.googleapis.com/auth/webmasters.readonly"
      assert_includes scopes, "https://www.googleapis.com/auth/analytics.readonly"
      assert_equal response.location, flash[:notice].match(/OAuth開始URL: (.+)\z/m)[1]
      assert_includes flash[:notice], "Client ID: env-client"
      assert_includes flash[:notice], "Redirect URI: #{admin_analytics_oauth_callback_url}"
      assert_includes flash[:notice], "access_type: offline"
      assert_includes flash[:notice], "prompt: consent"
      assert_includes flash[:notice], "source: all"
      assert_includes flash[:notice], "Google Credential ID:"
    end

    test "connect from business google settings records business context and exact oauth url" do
      business = businesses(:suelog)
      credential = AicooGoogleCredential.create!(
        name: "吸えログGoogle認証",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        google_cloud_project_id: "aicoo-500805",
        enabled: true
      )

      get admin_analytics_oauth_connect_url,
          params: {
            google_credential_id: credential.id,
            business_id: business.id,
            business_name: business.name,
            source: "ga4"
          }

      assert_response :redirect
      uri = URI.parse(response.location)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "705900000000-new.apps.googleusercontent.com", params["client_id"]
      assert_equal admin_analytics_oauth_callback_url, params["redirect_uri"]
      assert_equal "offline", params["access_type"]
      assert_equal "consent", params["prompt"]
      assert_equal business.name, params["state"]
      assert_equal credential.id, session[:analytics_oauth_google_credential_id]
      assert_equal business.id, session[:analytics_oauth_business_id]
      assert_equal "ga4", session[:analytics_oauth_source_key]
      assert_includes flash[:notice], "Google Credential ID: #{credential.id}"
      assert_includes flash[:notice], "Client ID: 705900000000-new.apps.googleusercontent.com"
      assert_includes flash[:notice], "Redirect URI: #{admin_analytics_oauth_callback_url}"
      assert_includes flash[:notice], "source: ga4"
      assert_includes flash[:notice], "business_id: #{business.id}"
      assert_includes flash[:notice], "OAuth開始URL: #{response.location}"
    end

    test "callback saves refresh token to gsc and ga4 settings for selected business" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = create_ga4_setting(name: "吸えログ GA4", property_id: "536889590")

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret",
        "GOOGLE_CLOUD_PROJECT" => "aicoo-500805"
      ) do
        with_oauth_exchange(refresh_token: "new-refresh-token") do
          get admin_analytics_oauth_callback_url, params: { code: "auth-code", state: "吸えログ" }
        end
      end

      assert_redirected_to admin_google_credentials_url
      credential = AicooGoogleCredential.default
      assert_equal "env-client", credential.client_id
      assert_equal "env-secret", credential.client_secret
      assert_equal "aicoo-500805", credential.google_cloud_project_id
      assert_equal "new-refresh-token", credential.refresh_token
      assert_equal "access-token", credential.access_token
      assert_equal "owner@example.com", credential.google_account_email
      assert credential.token_expires_at.present?
      assert credential.connected_at.present?
      assert credential.last_oauth_success_at.present?
      [ gsc.reload, ga4.reload ].each do |setting|
        assert_equal credential, setting.google_credential
        assert_nil setting.client_id
        assert_nil setting.client_secret
        assert_nil setting.refresh_token
        assert_nil setting.credentials_json
        assert setting.oauth_connected_at.present?
      end
    end

    test "callback can reauthenticate only ga4 settings for selected business" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = create_ga4_setting(name: "吸えログ GA4", property_id: "536889590")
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "old-refresh"
      )

      get admin_analytics_oauth_connect_url,
          params: { google_credential_id: credential.id, business_name: "吸えログ", source: "ga4" }

      with_oauth_exchange(refresh_token: "new-refresh-token") do
        get admin_analytics_oauth_callback_url, params: { code: "auth-code", state: "吸えログ" }
      end

      assert_redirected_to admin_google_credentials_url
      assert_nil gsc.reload.google_credential
      assert_equal credential.reload, ga4.reload.google_credential
      assert_equal "new-refresh-token", credential.refresh_token
    end

    test "callback persists remembered saved google credential values and reloads db state" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        refresh_token: nil,
        enabled: true
      )

      get admin_analytics_oauth_connect_url, params: { google_credential_id: credential.id }

      with_oauth_exchange(refresh_token: "fresh-refresh-token") do |captured|
        get admin_analytics_oauth_callback_url, params: { code: "auth-code" }

        assert_equal "705900000000-new.apps.googleusercontent.com", captured[:client_id]
        assert_equal "new-secret", captured[:client_secret]
      end

      assert_redirected_to admin_google_credentials_url
      credential.reload
      assert_equal "705900000000-new.apps.googleusercontent.com", credential.client_id
      assert_equal "new-secret", credential.client_secret
      assert_equal "aicoo-500805", credential.google_cloud_project_id
      assert_equal "fresh-refresh-token", credential.refresh_token
      assert_equal "access-token", credential.access_token
      assert credential.token_expires_at.present?
      assert_equal "owner@example.com", credential.google_account_email
      assert credential.last_oauth_success_at.present?
      assert_predicate credential, :connected?
    end

    test "callback uses the client credentials remembered at connect time" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = create_ga4_setting(name: "吸えログ GA4", property_id: "536889590")
      gsc.update!(
        client_id: "old-saved-client",
        client_secret: "old-saved-secret",
        credentials_json: '{"client_id":"old-json-client"}'
      )

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret"
      ) do
        get admin_analytics_oauth_connect_url, params: { business_name: "吸えログ" }

        with_oauth_exchange(refresh_token: "new-refresh-token") do |captured|
          get admin_analytics_oauth_callback_url, params: { code: "auth-code", state: "吸えログ" }

          assert_equal "env-client", captured[:client_id]
          assert_equal "env-secret", captured[:client_secret]
        end
      end

      [ gsc.reload, ga4.reload ].each do |setting|
        assert_equal AicooGoogleCredential.default, setting.google_credential
        assert_nil setting.client_id
        assert_nil setting.client_secret
        assert_nil setting.refresh_token
        assert_nil setting.credentials_json
        assert setting.oauth_connected_at.present?
      end
    end

    test "connect with a saved google credential does not use stale env client" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO新Google認証",
        client_id: "999999999999-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        enabled: true
      )

      with_google_env(
        "GOOGLE_CLIENT_ID" => "338488400527-old.apps.googleusercontent.com",
        "GOOGLE_CLIENT_SECRET" => "old-secret"
      ) do
        get admin_analytics_oauth_connect_url, params: { google_credential_id: credential.id }
      end

      assert_response :redirect
      uri = URI.parse(response.location)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "999999999999-new.apps.googleusercontent.com", params["client_id"]
    end

    test "connect generates oauth url from the requested credential record" do
      old_credential = AicooGoogleCredential.create!(
        name: "古いGoogle認証",
        client_id: "338488400527-old.apps.googleusercontent.com",
        client_secret: "old-secret",
        enabled: true
      )
      new_credential = AicooGoogleCredential.create!(
        name: "新しいGoogle認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        enabled: true
      )

      get admin_analytics_oauth_connect_url, params: { google_credential_id: new_credential.id }

      assert_response :redirect
      uri = URI.parse(response.location)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "705900000000-new.apps.googleusercontent.com", params["client_id"]
      assert_not_equal old_credential.client_id, params["client_id"]
      assert_equal new_credential.id, session[:analytics_oauth_google_credential_id]
      assert_equal "705900000000-new.apps.googleusercontent.com", session[:analytics_oauth_client_id]
      assert_equal "aicoo-500805", session[:analytics_oauth_google_cloud_project_id]
    end

    test "connect ignores stale remembered client when a credential record is requested" do
      old_credential = AicooGoogleCredential.create!(
        name: "古いGoogle認証",
        client_id: "338488400527-old.apps.googleusercontent.com",
        client_secret: "old-secret",
        enabled: true
      )
      new_credential = AicooGoogleCredential.create!(
        name: "新しいGoogle認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        enabled: true
      )

      get admin_analytics_oauth_connect_url, params: { google_credential_id: old_credential.id }
      assert_equal old_credential.client_id, session[:analytics_oauth_client_id]

      get admin_analytics_oauth_connect_url, params: { google_credential_id: new_credential.id }

      assert_response :redirect
      uri = URI.parse(response.location)
      params = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "705900000000-new.apps.googleusercontent.com", params["client_id"]
      assert_equal new_credential.id, session[:analytics_oauth_google_credential_id]
      assert_equal "705900000000-new.apps.googleusercontent.com", session[:analytics_oauth_client_id]
      assert_equal "aicoo-500805", session[:analytics_oauth_google_cloud_project_id]
    end

    test "analytics connections page shows latest oauth connected time" do
      setting = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      setting.update!(oauth_connected_at: Time.zone.local(2026, 6, 22, 12, 0, 0), refresh_token: "saved-refresh")

      get admin_analytics_connections_url

      assert_response :success
      assert_includes response.body, "最終OAuth接続"
      assert_includes response.body, I18n.l(setting.oauth_connected_at, format: :short)
    end

    test "connect shows clear error when client credentials are missing" do
      with_google_env({}) do
        get admin_analytics_oauth_connect_url
      end

      assert_redirected_to admin_google_credentials_url
      follow_redirect!
      assert_includes response.body, "Google OAuth Client ID / Secret が未設定です"
    end

    test "callback displays oauth error from google" do
      get admin_analytics_oauth_callback_url, params: { error: "unauthorized_client", error_description: "bad client" }

      assert_redirected_to admin_google_credentials_url
      follow_redirect!
      assert_includes response.body, "unauthorized_client"
      assert_includes response.body, "bad client"
    end

    test "callback displays helpful access denied guidance" do
      get admin_analytics_oauth_callback_url, params: { error: "access_denied", error_description: "審査プロセスを完了していません" }

      assert_redirected_to admin_google_credentials_url
      follow_redirect!
      assert_includes response.body, "Google認証に失敗しました"
      assert_includes response.body, "OAuth同意画面がテストモード"
      assert_includes response.body, "aicoo-500805"
      assert_includes response.body, "abclologun@gmail.com"
      assert_includes response.body, "https://aicoo.onrender.com/admin/analytics_oauth/callback"
    end

    test "callback displays token exchange failure" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret"
      ) do
        with_oauth_exchange_error("Google OAuth token exchange failed: 400 invalid_grant") do
          get admin_analytics_oauth_callback_url, params: { code: "auth-code", state: "吸えログ" }
        end
      end

      assert_redirected_to admin_google_credentials_url
      follow_redirect!
      assert_includes response.body, "invalid_grant"
    end

    test "callback does not succeed when refresh token is missing" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "new-secret",
        enabled: true
      )

      get admin_analytics_oauth_connect_url, params: { google_credential_id: credential.id }

      with_oauth_exchange(refresh_token: nil) do
        get admin_analytics_oauth_callback_url, params: { code: "auth-code" }
      end

      assert_redirected_to admin_google_credentials_url
      follow_redirect!
      assert_includes response.body, "Refresh Tokenが保存されませんでした"
      assert_nil credential.reload.refresh_token
      assert_nil credential.last_oauth_success_at
    end

    private

    def create_gsc_setting(name:, site_url:)
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name:,
        site_url:,
        enabled: true
      )
    end

    def create_ga4_setting(name:, property_id:)
      AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name:,
        property_id:,
        enabled: true
      )
    end

    def with_oauth_exchange(refresh_token:)
      captured = {}
      original_exchange = AicooAnalytics::GoogleOauthAuthorization.method(:exchange_code)
      AicooAnalytics::GoogleOauthAuthorization.define_singleton_method(:exchange_code) do |**kwargs|
        captured.merge!(kwargs)
        AicooAnalytics::GoogleOauthAuthorization::TokenResponse.new("access-token", refresh_token, 3600, "owner@example.com")
      end
      yield captured
    ensure
      AicooAnalytics::GoogleOauthAuthorization.define_singleton_method(:exchange_code) do |*args, **kwargs, &block|
        original_exchange.call(*args, **kwargs, &block)
      end
    end

    def with_oauth_exchange_error(message)
      original_exchange = AicooAnalytics::GoogleOauthAuthorization.method(:exchange_code)
      AicooAnalytics::GoogleOauthAuthorization.define_singleton_method(:exchange_code) do |**_kwargs|
        raise AicooAnalytics::GoogleOauthAuthorization::Error, message
      end
      yield
    ensure
      AicooAnalytics::GoogleOauthAuthorization.define_singleton_method(:exchange_code) do |*args, **kwargs, &block|
        original_exchange.call(*args, **kwargs, &block)
      end
    end

    def with_google_env(values)
      keys = %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN GOOGLE_CLOUD_PROJECT GOOGLE_PROJECT_ID]
      previous = keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
      keys.each { |key| ENV.delete(key) }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      keys.each { |key| previous[key].nil? ? ENV.delete(key) : ENV[key] = previous[key] }
    end
  end
end

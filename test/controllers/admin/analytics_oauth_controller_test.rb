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
    end

    test "callback saves refresh token to gsc and ga4 settings for selected business" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = create_ga4_setting(name: "吸えログ GA4", property_id: "536889590")

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret"
      ) do
        with_oauth_exchange(refresh_token: "new-refresh-token") do
          get admin_analytics_oauth_callback_url, params: { code: "auth-code", state: "吸えログ" }
        end
      end

      assert_redirected_to admin_analytics_connections_url
      [ gsc.reload, ga4.reload ].each do |setting|
        assert_equal "env-client", setting.client_id
        assert_equal "env-secret", setting.client_secret
        assert_equal "new-refresh-token", setting.refresh_token
        assert_nil setting.credentials_json
        assert setting.oauth_connected_at.present?
      end
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
        assert_equal "env-client", setting.client_id
        assert_equal "env-secret", setting.client_secret
        assert_equal "new-refresh-token", setting.refresh_token
        assert_nil setting.credentials_json
        assert setting.oauth_connected_at.present?
      end
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

      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "Google OAuth Client ID / Secret が未設定です"
    end

    test "callback displays oauth error from google" do
      get admin_analytics_oauth_callback_url, params: { error: "unauthorized_client", error_description: "bad client" }

      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "unauthorized_client"
      assert_includes response.body, "bad client"
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

      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "invalid_grant"
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
        AicooAnalytics::GoogleOauthAuthorization::TokenResponse.new("access-token", refresh_token)
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
      keys = %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN]
      previous = keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
      keys.each { |key| ENV.delete(key) }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      keys.each { |key| previous[key].nil? ? ENV.delete(key) : ENV[key] = previous[key] }
    end
  end
end

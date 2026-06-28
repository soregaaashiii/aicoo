require "test_helper"

module AicooAnalytics
  class GoogleAccessTokenTest < ActiveSupport::TestCase
    test "uses saved setting credentials before env credentials" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp",
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token",
        authentication_mode: "individual"
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "saved-client", fake_client.kwargs[:client_id]
      assert_equal "saved-secret", fake_client.kwargs[:client_secret]
      assert_equal "saved-refresh-token", fake_client.kwargs[:refresh_token]
      assert_equal(
        "client_id_source=setting client_secret_source=setting refresh_token_source=setting credentials_json_source=missing oauth_connected_at=missing",
        fake_client.kwargs[:credential_source_summary]
      )
    end

    test "falls back to common google credential values" do
      credential = AicooGoogleCredential.create!(
        name: "Common Google",
        client_id: "common-client",
        client_secret: "common-secret",
        refresh_token: "common-refresh-token",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "536889590",
        google_credential: credential
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "common-client", fake_client.kwargs[:client_id]
      assert_equal "common-secret", fake_client.kwargs[:client_secret]
      assert_equal "common-refresh-token", fake_client.kwargs[:refresh_token]
      assert_equal(
        "client_id_source=google_credential client_secret_source=google_credential refresh_token_source=google_credential credentials_json_source=missing oauth_connected_at=missing",
        fake_client.kwargs[:credential_source_summary]
      )
    end

    test "uses active common google credential when setting has no credential reference" do
      AicooGoogleCredential.create!(
        name: "Default Common Google",
        client_id: "default-client",
        client_secret: "default-secret",
        refresh_token: "default-refresh-token",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp"
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "default-client", fake_client.kwargs[:client_id]
      assert_equal "default-secret", fake_client.kwargs[:client_secret]
      assert_equal "default-refresh-token", fake_client.kwargs[:refresh_token]
      assert_includes fake_client.kwargs[:credential_source_summary], "client_id_source=google_credential"
    end

    test "falls back to env credentials when setting credentials are blank" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp"
      )
      fake_client = FakeOauthClient.new

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret",
        "GOOGLE_REFRESH_TOKEN" => "env-refresh-token"
      ) do
        with_oauth_client(fake_client) do
          assert_equal "access-token", GoogleAccessToken.new(setting).call
        end
      end

      assert_equal "env-client", fake_client.kwargs[:client_id]
      assert_equal "env-secret", fake_client.kwargs[:client_secret]
      assert_equal "env-refresh-token", fake_client.kwargs[:refresh_token]
    end

    test "uses common google credential before env credentials" do
      credential = AicooGoogleCredential.create!(
        name: "Common Google",
        client_id: "common-client",
        client_secret: "common-secret",
        refresh_token: "common-refresh-token",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "536889590",
        google_credential: credential
      )
      fake_client = FakeOauthClient.new

      with_google_env(
        "GOOGLE_CLIENT_ID" => "env-client",
        "GOOGLE_CLIENT_SECRET" => "env-secret",
        "GOOGLE_REFRESH_TOKEN" => "env-refresh-token"
      ) do
        with_oauth_client(fake_client) do
          assert_equal "access-token", GoogleAccessToken.new(setting).call
        end
      end

      assert_equal "common-client", fake_client.kwargs[:client_id]
      assert_equal "common-secret", fake_client.kwargs[:client_secret]
      assert_equal "common-refresh-token", fake_client.kwargs[:refresh_token]
      assert_equal(
        "client_id_source=google_credential client_secret_source=google_credential refresh_token_source=google_credential credentials_json_source=missing oauth_connected_at=missing",
        fake_client.kwargs[:credential_source_summary]
      )
    end

    test "does not fall back to stale env when configured google credential needs reauthentication" do
      AicooGoogleCredential.create!(
        name: "Common Google",
        client_id: "new-client",
        client_secret: "new-secret",
        refresh_token: nil
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "536889590"
      )
      fake_client = FakeOauthClient.new

      with_google_env(
        "GOOGLE_CLIENT_ID" => "old-env-client",
        "GOOGLE_CLIENT_SECRET" => "old-env-secret",
        "GOOGLE_REFRESH_TOKEN" => "old-env-refresh-token"
      ) do
        with_oauth_client(fake_client) do
          assert_equal "access-token", GoogleAccessToken.new(setting).call
        end
      end

      assert_equal "new-client", fake_client.kwargs[:client_id]
      assert_equal "new-secret", fake_client.kwargs[:client_secret]
      assert_nil fake_client.kwargs[:refresh_token]
      assert_equal(
        "client_id_source=google_credential client_secret_source=google_credential refresh_token_source=google_credential credentials_json_source=missing oauth_connected_at=missing",
        fake_client.kwargs[:credential_source_summary]
      )
    end

    test "credential source summary includes oauth connected status" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog connected GSC",
        site_url: "sc-domain:suelog.jp",
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token",
        oauth_connected_at: Time.current
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_includes fake_client.kwargs[:credential_source_summary], "oauth_connected_at=present"
    end

    test "uses saved credentials when credentials json is nil" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp",
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token",
        credentials_json: nil,
        authentication_mode: "individual"
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "saved-client", fake_client.kwargs[:client_id]
      assert_equal "saved-secret", fake_client.kwargs[:client_secret]
      assert_equal "saved-refresh-token", fake_client.kwargs[:refresh_token]
    end

    test "individual mode does not fall back to common google credential" do
      AicooGoogleCredential.create!(
        name: "Common Google",
        client_id: "common-client",
        client_secret: "common-secret",
        refresh_token: "common-refresh-token",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Individual missing GSC",
        site_url: "sc-domain:suelog.jp",
        authentication_mode: "individual"
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_nil fake_client.kwargs[:client_id]
      assert_nil fake_client.kwargs[:client_secret]
      assert_nil fake_client.kwargs[:refresh_token]
      assert_includes fake_client.kwargs[:credential_source_summary], "client_id_source=missing"
    end

    private

    def with_oauth_client(fake_client)
      original_new = GoogleOauthClient.method(:new)
      GoogleOauthClient.define_singleton_method(:new) do |**kwargs|
        fake_client.tap { |client| client.kwargs = kwargs }
      end
      yield
    ensure
      GoogleOauthClient.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    class FakeOauthClient
      attr_accessor :kwargs

      def access_token
        "access-token"
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

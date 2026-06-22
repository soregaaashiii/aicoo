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
        refresh_token: "saved-refresh-token"
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

    test "falls back to credentials json values" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "536889590",
        credentials_json: '{"client_id":"json-client","client_secret":"json-secret","refresh_token":"json-refresh-token"}'
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "json-client", fake_client.kwargs[:client_id]
      assert_equal "json-secret", fake_client.kwargs[:client_secret]
      assert_equal "json-refresh-token", fake_client.kwargs[:refresh_token]
      assert_equal(
        "client_id_source=credentials_json client_secret_source=credentials_json refresh_token_source=credentials_json credentials_json_source=setting oauth_connected_at=missing",
        fake_client.kwargs[:credential_source_summary]
      )
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

    test "uses env credentials before credentials json" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "536889590",
        credentials_json: '{"client_id":"json-client","client_secret":"json-secret","refresh_token":"json-refresh-token"}'
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
      assert_equal(
        "client_id_source=env client_secret_source=env refresh_token_source=env credentials_json_source=setting oauth_connected_at=missing",
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
        credentials_json: nil
      )
      fake_client = FakeOauthClient.new

      with_oauth_client(fake_client) do
        assert_equal "access-token", GoogleAccessToken.new(setting).call
      end

      assert_equal "saved-client", fake_client.kwargs[:client_id]
      assert_equal "saved-secret", fake_client.kwargs[:client_secret]
      assert_equal "saved-refresh-token", fake_client.kwargs[:refresh_token]
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

require "test_helper"

module Admin
  class AnalyticsConnectionsControllerTest < ActionDispatch::IntegrationTest
    test "shows analytics connections page" do
      create_gsc_setting(name: "吸えログ", site_url: "sc-domain:suelog.jp")
      create_ga4_setting(name: "吸えログ", property_id: "536889590")

      get admin_analytics_connections_url

      assert_response :success
      assert_includes response.body, "分析設定"
      assert_includes response.body, "事業別分析設定"
      assert_includes response.body, "分析設定を追加"
      assert_includes response.body, "Google認証情報"
      assert_includes response.body, "GOOGLE_CLIENT_ID"
      assert_includes response.body, "GOOGLE_CLIENT_SECRET"
      assert_includes response.body, "GOOGLE_REFRESH_TOKEN"
      assert_includes response.body, "google_client_id"
      assert_includes response.body, "google_client_secret"
      assert_includes response.body, "google_refresh_token"
      assert_includes response.body, "credentials_json"
      assert_includes response.body, "Googleと接続"
      assert_includes response.body, "Google認証"
      assert_includes response.body, "refresh_token"
      assert_includes response.body, "GSC設定"
      assert_includes response.body, "GA4設定"
      assert_includes response.body, "取得対象にする"
      assert_includes response.body, "Google認証の接続状態や、取得成功を意味する項目ではありません"
      assert_includes response.body, "データ取得対象"
      assert_includes response.body, "取得する"
      assert_includes response.body, "取得日数"
      assert_includes response.body, "吸えログ"
      assert_includes response.body, "吸えログの分析設定"
      assert_includes response.body, "sc-domain:suelog.jp"
      assert_includes response.body, "536889590"
      assert_includes response.body, "GSC状態"
      assert_includes response.body, "GA4状態"
      assert_includes response.body, "認証状態"
      assert_includes response.body, "client_id"
      assert_includes response.body, "client_secret"
      assert_includes response.body, "refresh_token"
      assert_includes response.body, "credentials_json"
      assert_includes response.body, "最終OAuth接続"
      assert_includes response.body, "GSC取得"
      assert_includes response.body, "GA4取得"
      assert_includes response.body, "両方取得"
      assert_includes response.body, "編集"
      assert_includes response.body, "上級者向け設定を開く"
      assert_not_includes response.body, "source_type"
      assert_not_includes response.body, "secret-refresh-token"
    end

    test "shows env credential statuses" do
      with_google_env(
        "GOOGLE_CLIENT_ID" => "client-id",
        "GOOGLE_CLIENT_SECRET" => "client-secret",
        "GOOGLE_REFRESH_TOKEN" => "refresh-token"
      ) do
        get admin_analytics_connections_url
      end

      assert_response :success
      assert_includes response.body, "GOOGLE_CLIENT_ID"
      assert_includes response.body, "GOOGLE_CLIENT_SECRET"
      assert_includes response.body, "GOOGLE_REFRESH_TOKEN"
      assert_includes response.body, "設定済み"
      assert_not_includes response.body, "client-secret"
      assert_not_includes response.body, "refresh-token"
    end

    test "saves gsc and ga4 settings for one business" do
      assert_difference("AnalyticsSourceSetting.count", 2) do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "sc-domain:suelog.jp",
            ga4_property_id: "536889590",
            enabled: "1",
            fetch_days: "14"
          }
        }
      end

      assert_redirected_to admin_analytics_connections_url
      assert AnalyticsSourceSetting.exists?(source_type: "gsc", name: "吸えログ GSC", site_url: "sc-domain:suelog.jp", enabled: true, fetch_days: 14)
      assert AnalyticsSourceSetting.exists?(source_type: "ga4", name: "吸えログ GA4", property_id: "536889590", enabled: true, fetch_days: 14)
    end

    test "saves refresh token from analytics connections screen" do
      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "",
          google_refresh_token: "new-refresh-token",
          enabled: "1",
          fetch_days: "28"
        }
      }

      setting = AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC")
      assert_equal "new-refresh-token", setting.refresh_token
      assert_includes setting.credentials_json, "new-refresh-token"
    end

    test "blank credential save does not clear existing refresh token" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:old.jp")

      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "",
          google_refresh_token: "",
          credentials_json: "",
          enabled: "1",
          fetch_days: "28"
        }
      }

      setting = AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC")
      assert_equal "secret-refresh-token", setting.refresh_token
    end

    test "blank credential save does not clear existing credentials json" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp").update!(
        credentials_json: '{"client_id":"json-client"}'
      )

      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "",
          google_client_id: "",
          google_client_secret: "",
          google_refresh_token: "",
          credentials_json: "",
          enabled: "1",
          fetch_days: "28"
        }
      }

      setting = AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC")
      assert_includes setting.credentials_json, "json-client"
    end

    test "saves credentials json from analytics connections screen" do
      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "",
          credentials_json: '{"client_id":"json-client","client_secret":"json-secret"}',
          enabled: "1",
          fetch_days: "28"
        }
      }

      setting = AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC")
      assert_includes setting.credentials_json, "json-client"
      assert_includes setting.credentials_json, "json-secret"
    end

    test "applies common credentials to gsc and ga4 settings" do
      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "536889590",
          google_client_id: " \"shared-client\" ",
          google_client_secret: " 'shared-secret' ",
          google_refresh_token: " shared-refresh-token \"",
          enabled: "1",
          fetch_days: "28"
        }
      }

      gsc = AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC")
      ga4 = AnalyticsSourceSetting.find_by!(source_type: "ga4", name: "吸えログ GA4")
      [ gsc, ga4 ].each do |setting|
        assert_equal "shared-client", setting.client_id
        assert_equal "shared-secret", setting.client_secret
        assert_equal "shared-refresh-token", setting.refresh_token
        assert_includes setting.credentials_json, "shared-client"
        assert_includes setting.credentials_json, "shared-secret"
        assert_includes setting.credentials_json, "shared-refresh-token"
      end
    end

    test "shows saved credential statuses without revealing values" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp").update!(
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token",
        credentials_json: '{"client_id":"json-client"}'
      )

      get admin_analytics_connections_url

      assert_response :success
      assert_includes response.body, "client_id"
      assert_includes response.body, "client_secret"
      assert_includes response.body, "refresh_token"
      assert_includes response.body, "credentials_json"
      assert_includes response.body, "設定済み"
      assert_not_includes response.body, "saved-secret"
      assert_not_includes response.body, "saved-refresh-token"
      assert_not_includes response.body, "json-client"
    end

    test "deletes credentials json for gsc and ga4 while preserving direct credentials" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = create_ga4_setting(name: "吸えログ GA4", property_id: "536889590")
      [ gsc, ga4 ].each do |setting|
        setting.update!(
          client_id: "saved-client",
          client_secret: "saved-secret",
          refresh_token: "saved-refresh-token",
          credentials_json: '{"client_id":"old-json-client","client_secret":"old-json-secret","refresh_token":"old-json-refresh"}'
        )
      end

      post delete_credentials_json_admin_analytics_connections_url, params: { business_name: "吸えログ" }

      assert_redirected_to admin_analytics_connections_url
      [ gsc.reload, ga4.reload ].each do |setting|
        assert_nil setting.credentials_json
        assert_equal "saved-client", setting.client_id
        assert_equal "saved-secret", setting.client_secret
        assert_equal "saved-refresh-token", setting.refresh_token
        assert_includes AicooAnalytics::GoogleAccessToken.new(setting).credential_source_summary, "credentials_json_source=missing"
      end
    end

    test "blank save after credentials json deletion does not recreate credentials json" do
      setting = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      setting.update!(
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token",
        credentials_json: '{"client_id":"old-json-client"}'
      )

      post delete_credentials_json_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "",
          google_client_id: "",
          google_client_secret: "",
          google_refresh_token: "",
          credentials_json: "",
          enabled: "1",
          fetch_days: "28"
        }
      }

      setting.reload
      assert_nil setting.credentials_json
      assert_equal "saved-client", setting.client_id
      assert_equal "saved-secret", setting.client_secret
      assert_equal "saved-refresh-token", setting.refresh_token
    end

    test "inherits existing credentials when adding the other analytics source later" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp").update!(
        client_id: "existing-client",
        client_secret: "existing-secret",
        refresh_token: "existing-refresh-token"
      )

      post admin_analytics_connections_url, params: {
        analytics_connection: {
          business_name: "吸えログ",
          gsc_site_url: "sc-domain:suelog.jp",
          ga4_property_id: "536889590",
          enabled: "1",
          fetch_days: "28"
        }
      }

      ga4 = AnalyticsSourceSetting.find_by!(source_type: "ga4", name: "吸えログ GA4")
      assert_equal "existing-client", ga4.client_id
      assert_equal "existing-secret", ga4.client_secret
      assert_equal "existing-refresh-token", ga4.refresh_token
    end

    test "saves only gsc setting" do
      assert_difference("AnalyticsSourceSetting.count", 1) do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "sc-domain:suelog.jp",
            ga4_property_id: "",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_redirected_to admin_analytics_connections_url
      assert AnalyticsSourceSetting.exists?(source_type: "gsc", name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      assert_not AnalyticsSourceSetting.exists?(source_type: "ga4", name: "吸えログ GA4")
    end

    test "saves only ga4 setting" do
      assert_difference("AnalyticsSourceSetting.count", 1) do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "",
            ga4_property_id: "536889590",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_redirected_to admin_analytics_connections_url
      assert AnalyticsSourceSetting.exists?(source_type: "ga4", name: "吸えログ GA4", property_id: "536889590")
      assert_not AnalyticsSourceSetting.exists?(source_type: "gsc", name: "吸えログ GSC")
    end

    test "does not save when both identifiers are blank" do
      assert_no_difference("AnalyticsSourceSetting.count") do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "",
            ga4_property_id: "",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_response :unprocessable_content
      assert_includes response.body, "GSCまたはGA4のどちらかを設定してください"
    end

    test "blank save disables existing settings without clearing credentials" do
      gsc = create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:suelog.jp")
      ga4 = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "吸えログ GA4",
        property_id: "536889590",
        enabled: true,
        credentials_json: "{\"client\":\"secret\"}",
        refresh_token: "ga4-refresh-token"
      )

      assert_no_difference("AnalyticsSourceSetting.count") do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "",
            ga4_property_id: "",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_response :unprocessable_content
      assert_not AnalyticsSourceSetting.find(gsc.id).enabled?
      reloaded_ga4 = AnalyticsSourceSetting.find(ga4.id)
      assert_not reloaded_ga4.enabled?
      assert_equal "{\"client\":\"secret\"}", reloaded_ga4.credentials_json
      assert_equal "ga4-refresh-token", reloaded_ga4.refresh_token
    end

    test "updates existing settings without creating duplicates" do
      create_gsc_setting(name: "吸えログ GSC", site_url: "sc-domain:old.jp")
      create_ga4_setting(name: "吸えログ GA4", property_id: "111")

      assert_no_difference("AnalyticsSourceSetting.count") do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "sc-domain:suelog.jp",
            ga4_property_id: "536889590",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_redirected_to admin_analytics_connections_url
      assert_equal "sc-domain:suelog.jp", AnalyticsSourceSetting.find_by!(source_type: "gsc", name: "吸えログ GSC").site_url
      assert_equal "536889590", AnalyticsSourceSetting.find_by!(source_type: "ga4", name: "吸えログ GA4").property_id
    end

    test "does not create duplicate when existing setting has same identifier" do
      create_gsc_setting(name: "旧設定", site_url: "sc-domain:suelog.jp")

      assert_no_difference("AnalyticsSourceSetting.count") do
        post admin_analytics_connections_url, params: {
          analytics_connection: {
            business_name: "吸えログ",
            gsc_site_url: "sc-domain:suelog.jp",
            ga4_property_id: "",
            enabled: "1",
            fetch_days: "28"
          }
        }
      end

      assert_redirected_to admin_analytics_connections_url
      setting = AnalyticsSourceSetting.find_by!(source_type: "gsc", site_url: "sc-domain:suelog.jp")
      assert_equal "吸えログ GSC", setting.name
    end

    test "groups existing suffixed gsc and ga4 names into one business card" do
      create_gsc_setting(name: "吸えログGSC", site_url: "sc-domain:suelog.jp")
      create_ga4_setting(name: "吸えログGA4", property_id: "536889590")

      get admin_analytics_connections_url

      assert_response :success
      assert_includes response.body, "吸えログの分析設定"
      assert_not_includes response.body, "吸えログGSCの分析設定"
      assert_not_includes response.body, "吸えログGA4の分析設定"
    end

    test "normal analytics connection page does not expose separate source creation buttons" do
      get admin_analytics_connections_url

      assert_response :success
      assert_not_includes response.body, "GSC設定を作成"
      assert_not_includes response.body, "GA4設定を作成"
      assert_not_includes response.body, "source_type"
    end

    test "fetches gsc for business" do
      setting = create_gsc_setting(name: "吸えログ", site_url: "sc-domain:suelog.jp")
      run = create_fetch_run(setting:, status: "success")
      fake_runner = FakeRunner.new(run)

      with_runner_stub(fake_runner) do
        post fetch_gsc_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      end

      assert fake_runner.called
      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "GSC取得成功。"
      assert_includes response.body, "GA4が未設定です。GSCのみ取得できます。"
    end

    test "fetches ga4 for business" do
      setting = create_ga4_setting(name: "吸えログ", property_id: "536889590")
      run = create_fetch_run(setting:, status: "success")
      fake_runner = FakeRunner.new(run)

      with_runner_stub(fake_runner) do
        post fetch_ga4_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      end

      assert fake_runner.called
      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "GA4取得成功。"
      assert_includes response.body, "GSCが未設定です。GA4のみ取得できます。"
    end

    test "fetches both settings for business" do
      create_gsc_setting(name: "吸えログ", site_url: "sc-domain:suelog.jp")
      create_ga4_setting(name: "吸えログ", property_id: "536889590")
      fake_runner = CountingRunner.new

      with_runner_stub(fake_runner) do
        post fetch_all_for_business_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      end

      assert_equal 2, fake_runner.call_count
      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "GSC取得成功。 GA4取得成功。"
    end

    test "fetches configured source and skips missing source" do
      create_gsc_setting(name: "吸えログ", site_url: "sc-domain:suelog.jp")
      fake_runner = CountingRunner.new

      with_runner_stub(fake_runner) do
        post fetch_all_for_business_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      end

      assert_equal 1, fake_runner.call_count
      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "GSC取得成功。"
      assert_includes response.body, "GA4は未設定のためスキップしました。"
    end

    test "fetch all reports one failure and one success separately" do
      create_gsc_setting(name: "吸えログ", site_url: "sc-domain:suelog.jp")
      create_ga4_setting(name: "吸えログ", property_id: "536889590")
      fake_runner = SequentialRunner.new([ "failed", "success" ])

      with_runner_stub(fake_runner) do
        post fetch_all_for_business_admin_analytics_connections_url, params: { business_name: "吸えログ" }
      end

      assert_equal 2, fake_runner.call_count
      assert_redirected_to admin_analytics_connections_url
      follow_redirect!
      assert_includes response.body, "GSC取得失敗。fake failure"
      assert_includes response.body, "GA4取得成功。"
    end

    private

    def create_gsc_setting(name:, site_url:)
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name:,
        site_url:,
        enabled: true,
        refresh_token: "secret-refresh-token"
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

    def create_fetch_run(setting:, status:, error_message: nil)
      setting.analytics_fetch_runs.create!(
        source_type: setting.source_type,
        status:,
        error_message:,
        started_at: 1.minute.ago,
        finished_at: Time.current
      )
    end

    def with_runner_stub(fake_runner)
      original_new = AicooAnalytics::FetchRunner.method(:new)
      AicooAnalytics::FetchRunner.define_singleton_method(:new) { |_setting| fake_runner }
      yield
    ensure
      AicooAnalytics::FetchRunner.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
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

    class FakeRunner
      attr_reader :called

      def initialize(run)
        @run = run
        @called = false
      end

      def call
        @called = true
        @run
      end
    end

    class SequentialRunner
      Result = Data.define(:status, :error_message)

      attr_reader :call_count

      def initialize(statuses)
        @statuses = statuses
        @call_count = 0
      end

      def call
        status = @statuses.fetch(@call_count)
        @call_count += 1
        Result.new(status, status == "failed" ? "fake failure" : nil)
      end
    end

    class CountingRunner
      Result = Data.define(:status, :error_message)

      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def call
        @call_count += 1
        Result.new("success", nil)
      end
    end
  end
end

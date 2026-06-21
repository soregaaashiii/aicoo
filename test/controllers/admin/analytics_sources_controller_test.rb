require "test_helper"

module Admin
  class AnalyticsSourcesControllerTest < ActionDispatch::IntegrationTest
    test "shows analytics sources and manual fetch button" do
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp"
      )

      get admin_analytics_sources_url

      assert_response :success
      assert_includes response.body, "上級者向け設定"
      assert_includes response.body, "分析設定"
      assert_includes response.body, "GA4/GSC設定一覧"
      assert_includes response.body, "手動取得"
      assert_includes response.body, "分析設定で編集"
      assert_includes response.body, "/admin/analytics_connections"
      assert_includes response.body, "business_name=Suelog"
      assert_not_includes response.body, "GSC設定を作成"
      assert_not_includes response.body, "GA4設定を作成"
      assert_includes response.body, "定期実行コマンド"
      assert_includes response.body, "bin/rails aicoo:analytics:daily_fetch"
      assert_includes response.body, "定期取得準備チェック"
      assert_includes response.body, "チェックを再実行"
      assert_includes response.body, "取得履歴"
      assert_includes response.body, "Suelog GSC"
    end

    test "creates analytics source setting" do
      assert_difference("AnalyticsSourceSetting.count", 1) do
        post admin_analytics_sources_url, params: {
          analytics_source_setting: {
            source_type: "gsc",
            name: "Create GSC",
            site_url: "sc-domain:suelog.jp",
            fetch_days: 28,
            enabled: "1"
          }
        }
      end

      assert_redirected_to admin_analytics_sources_url
      assert_equal "gsc", AnalyticsSourceSetting.last.source_type
    end

    test "edit form shows current non-secret values and masks credentials" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Edit GSC",
        site_url: "sc-domain:suelog.jp",
        fetch_days: 14,
        enabled: true,
        credentials_json: '{"client_id":"secret-client"}',
        refresh_token: "secret-refresh-token"
      )

      get edit_admin_analytics_source_url(setting)

      assert_response :success
      assert_includes response.body, "Edit GSC"
      assert_includes response.body, "sc-domain:suelog.jp"
      assert_includes response.body, "14"
      assert_includes response.body, "認証情報設定済み"
      assert_not_includes response.body, "secret-client"
      assert_not_includes response.body, "secret-refresh-token"
    end

    test "ga4 edit form shows property id" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Edit GA4",
        property_id: "123456789",
        fetch_days: 28
      )

      get edit_admin_analytics_source_url(setting)

      assert_response :success
      assert_includes response.body, "123456789"
      assert_not_includes response.body, "Site URL（GSC用）"
    end

    test "blank credentials on update keep existing credential values" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Credential GSC",
        site_url: "sc-domain:suelog.jp",
        credentials_json: '{"client_id":"secret-client"}',
        refresh_token: "secret-refresh-token"
      )

      patch admin_analytics_source_url(setting), params: {
        analytics_source_setting: {
          source_type: "gsc",
          name: "Credential GSC Updated",
          site_url: "sc-domain:suelog.jp",
          fetch_days: 28,
          enabled: "1",
          credentials_json: "",
          refresh_token: ""
        }
      }

      assert_redirected_to admin_analytics_sources_url
      setting.reload
      assert_equal '{"client_id":"secret-client"}', setting.credentials_json
      assert_equal "secret-refresh-token", setting.refresh_token
      assert_equal "Credential GSC Updated", setting.name
    end

    test "duplicate enabled setting shows validation error on create" do
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Primary GSC",
        site_url: "sc-domain:suelog.jp",
        enabled: true
      )

      assert_no_difference("AnalyticsSourceSetting.count") do
        post admin_analytics_sources_url, params: {
          analytics_source_setting: {
            source_type: "gsc",
            name: "Duplicate GSC",
            site_url: "sc-domain:suelog.jp",
            fetch_days: 28,
            enabled: "1"
          }
        }
      end

      assert_response :unprocessable_content
      assert_includes response.body, "同じGSCサイトURLの有効設定が既に存在します"
    end

    test "index shows duplicate warning for existing duplicate enabled settings" do
      first = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Existing duplicate 1",
        site_url: "sc-domain:suelog.jp",
        enabled: true
      )
      second = AnalyticsSourceSetting.new(
        source_type: "gsc",
        name: "Existing duplicate 2",
        site_url: "sc-domain:suelog.jp",
        enabled: true
      )
      second.save!(validate: false)

      get admin_analytics_sources_url

      assert_response :success
      assert_includes response.body, first.site_url
      assert_includes response.body, "重複警告"
    end

    test "manual fetch calls fetcher and shows success" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Fetch GSC",
        site_url: "sc-domain:suelog.jp"
      )
      run = create_fetch_run(setting:, status: "success", snapshot_count: 1)
      fake_runner = FakeRunner.new(run)

      with_runner_stub(fake_runner) do
        post fetch_now_admin_analytics_source_url(setting)
      end

      assert fake_runner.called
      assert_redirected_to admin_analytics_sources_url
      follow_redirect!
      assert_includes response.body, "GSCを取得しました"
      assert_includes response.body, "Snapshot 1件作成"
    end

    test "manual fetch shows api error" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Fetch GA4",
        property_id: "123456789"
      )
      run = create_fetch_run(setting:, status: "failed", error_message: "fake failure")
      fake_runner = FakeRunner.new(run)

      with_runner_stub(fake_runner) do
        post fetch_now_admin_analytics_source_url(setting)
      end

      assert fake_runner.called
      assert_redirected_to admin_analytics_sources_url
      follow_redirect!
      assert_includes response.body, "分析データ取得に失敗しました: fake failure"
    end

    test "fetch all runs enabled settings" do
      AnalyticsSourceSetting.create!(source_type: "gsc", name: "Fetch all GSC", site_url: "sc-domain:suelog.jp")
      AnalyticsSourceSetting.create!(source_type: "ga4", name: "Fetch all GA4", property_id: "123456789")
      AnalyticsSourceSetting.create!(source_type: "gsc", name: "Disabled GSC", site_url: "sc-domain:disabled.jp", enabled: false)
      fake_runner = CountingRunner.new

      with_runner_stub(fake_runner) do
        post fetch_all_admin_analytics_sources_url
      end

      assert_equal 2, fake_runner.call_count
      assert_redirected_to admin_analytics_sources_url
      follow_redirect!
      assert_includes response.body, "全有効設定の取得を実行しました"
    end

    test "check readiness redirects to readiness panel" do
      post check_readiness_admin_analytics_sources_url

      assert_redirected_to "#{admin_analytics_sources_url}#schedule-readiness"
      follow_redirect!
      assert_includes response.body, "定期取得準備チェックを再実行しました"
    end

    private

    def create_fetch_run(setting:, status:, snapshot_count: 0, error_message: nil)
      data_import = create_data_import if status == "success"
      setting.analytics_fetch_runs.create!(
        source_type: setting.source_type,
        status:,
        started_at: 1.minute.ago,
        finished_at: Time.current,
        data_import_id: data_import&.id,
        snapshot_count:,
        updated_neglect_loss_count: 0,
        error_message:
      )
    end

    def create_data_import
      business = Business.create!(name: "Analytics source controller")
      data_source = business.data_sources.create!(name: "GSC source", source_type: "gsc")
      data_source.data_imports.create!(
        filename: "gsc.csv",
        content_type: "text/csv",
        row_count: 1,
        raw_text: "query,clicks\nsample,1\n",
        imported_at: Time.current
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

    class CountingRunner
      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def call
        @call_count += 1
      end
    end
  end
end

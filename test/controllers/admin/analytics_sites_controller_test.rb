require "test_helper"

module Admin
  class AnalyticsSitesControllerTest < ActionDispatch::IntegrationTest
    test "shows analytics sites index" do
      AicooAnalyticsSite.create!(name: "吸えログ", domain: "suelog.jp", gsc_site_url: "sc-domain:suelog.jp", ga4_property_id: "536889590")

      get admin_analytics_sites_url

      assert_response :success
      assert_includes response.body, "サイト別分析設定"
      assert_includes response.body, "吸えログ"
      assert_includes response.body, "sc-domain:suelog.jp"
      assert_includes response.body, "536889590"
      assert_includes response.body, "GSC取得"
      assert_includes response.body, "GA4取得"
      assert_includes response.body, "両方取得"
      assert_includes response.body, "認証方式"
      assert_includes response.body, "使用認証"
    end

    test "creates analytics site and source settings" do
      credential = create_google_credential

      assert_difference("AicooAnalyticsSite.count", 1) do
        assert_difference("AnalyticsSourceSetting.count", 2) do
          post admin_analytics_sites_url, params: {
            aicoo_analytics_site: {
              name: "吸えログ",
              public_url: "https://suelog.jp",
              domain: "suelog.jp",
              gsc_site_url: "sc-domain:suelog.jp",
              ga4_property_id: "536889590",
              authentication_mode: "shared",
              enabled: "1"
            }
          }
        end
      end

      site = AicooAnalyticsSite.find_by!(name: "吸えログ")
      gsc = AnalyticsSourceSetting.find_by!(source_type: "gsc", site_url: "sc-domain:suelog.jp")
      ga4 = AnalyticsSourceSetting.find_by!(source_type: "ga4", property_id: "536889590")
      assert_equal site, gsc.aicoo_analytics_site
      assert_equal site, ga4.aicoo_analytics_site
      assert_equal "shared", gsc.authentication_mode
      assert_equal "shared", ga4.authentication_mode
      assert_equal credential, gsc.google_credential
      assert_equal credential, ga4.google_credential
    end

    test "creates individual authentication source settings" do
      post admin_analytics_sites_url, params: {
        aicoo_analytics_site: {
          name: "個別サイト",
          gsc_site_url: "sc-domain:individual.jp",
          ga4_property_id: "123456789",
          authentication_mode: "individual",
          enabled: "1"
        }
      }

      site = AicooAnalyticsSite.find_by!(name: "個別サイト")
      [ site.gsc_setting, site.ga4_setting ].each do |setting|
        assert_equal "individual", setting.authentication_mode
        assert_nil setting.google_credential
      end
    end

    test "shows warning for individual authentication without credentials" do
      AicooAnalyticsSite.create!(name: "個別サイト", gsc_site_url: "sc-domain:individual.jp", authentication_mode: "individual")

      get admin_analytics_sites_url

      assert_response :success
      assert_includes response.body, "このサイトは個別認証を使う設定ですが、認証情報が未設定です"
    end

    test "shows warning for shared authentication without common credential" do
      AicooAnalyticsSite.create!(name: "共通サイト", gsc_site_url: "sc-domain:shared.jp", authentication_mode: "shared")

      get admin_analytics_sites_url

      assert_response :success
      assert_includes response.body, "AICOO共通Google認証が未接続です"
    end

    test "reuses existing source setting" do
      AnalyticsSourceSetting.create!(source_type: "gsc", name: "Old GSC", site_url: "sc-domain:suelog.jp")

      assert_no_difference("AnalyticsSourceSetting.count") do
        AicooAnalyticsSite.create!(name: "吸えログ", gsc_site_url: "sc-domain:suelog.jp")
      end

      assert_equal "吸えログ GSC", AnalyticsSourceSetting.find_by!(source_type: "gsc", site_url: "sc-domain:suelog.jp").name
    end

    test "saves only gsc or only ga4" do
      assert_difference("AnalyticsSourceSetting.where(source_type: 'gsc').count", 1) do
        AicooAnalyticsSite.create!(name: "GSC only", gsc_site_url: "sc-domain:gsc-only.jp")
      end

      assert_difference("AnalyticsSourceSetting.where(source_type: 'ga4').count", 1) do
        AicooAnalyticsSite.create!(name: "GA4 only", ga4_property_id: "123456789")
      end
    end

    test "fetch all runs configured sources and skips missing source" do
      site = AicooAnalyticsSite.create!(name: "吸えログ", gsc_site_url: "sc-domain:suelog.jp")
      fake_runner = CountingRunner.new

      with_runner_stub(fake_runner) do
        post fetch_all_admin_analytics_site_url(site)
      end

      assert_equal 1, fake_runner.call_count
      assert_redirected_to admin_analytics_sites_url
      follow_redirect!
      assert_includes response.body, "GSC取得成功。"
      assert_includes response.body, "GA4は未設定のためスキップしました。"
    end

    test "autolink creates analytics site from published landing pages" do
      landing_page = create_published_landing_page

      assert_difference("AicooAnalyticsSite.count", 1) do
        post autolink_admin_analytics_sites_url
      end

      site = AicooAnalyticsSite.find_by!(autolink_source_type: "AicooLabLandingPage", autolink_source_id: landing_page.id)
      assert_redirected_to admin_analytics_sites_url
      assert site.auto_created?
      assert_equal "shared", site.authentication_mode
    end

    test "shows gsc and ga4 missing warnings" do
      AicooAnalyticsSite.create!(name: "Auto LP", public_url: "https://lp.example.com", domain: "lp.example.com", auto_created: true)

      get admin_analytics_sites_url

      assert_response :success
      assert_includes response.body, "自動作成済み"
      assert_includes response.body, "GSC未設定"
      assert_includes response.body, "GA4未設定"
    end

    private

    def create_google_credential
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )
    end

    def create_published_landing_page
      experiment = AicooLabExperiment.create!(
        title: "Analytics autolink publish",
        experiment_type: "lp",
        acquisition_channel: "sns",
        status: "preview_ready",
        approval_status: "approved"
      )
      landing_page = experiment.create_aicoo_lab_landing_page!(
        headline: "Analytics autolink headline",
        subheadline: "Sub",
        body: "Body",
        cta_text: "登録する",
        status: "preview_ready"
      )
      landing_page.publish!
      landing_page
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

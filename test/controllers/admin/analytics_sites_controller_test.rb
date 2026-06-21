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
    end

    test "creates analytics site and source settings" do
      assert_difference("AicooAnalyticsSite.count", 1) do
        assert_difference("AnalyticsSourceSetting.count", 2) do
          post admin_analytics_sites_url, params: {
            aicoo_analytics_site: {
              name: "吸えログ",
              public_url: "https://suelog.jp",
              domain: "suelog.jp",
              gsc_site_url: "sc-domain:suelog.jp",
              ga4_property_id: "536889590",
              enabled: "1"
            }
          }
        end
      end

      site = AicooAnalyticsSite.find_by!(name: "吸えログ")
      assert_equal site, AnalyticsSourceSetting.find_by!(source_type: "gsc", site_url: "sc-domain:suelog.jp").aicoo_analytics_site
      assert_equal site, AnalyticsSourceSetting.find_by!(source_type: "ga4", property_id: "536889590").aicoo_analytics_site
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

    private

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

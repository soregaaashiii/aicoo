require "test_helper"

module Admin
  class GoogleApiImportsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @business = businesses(:suelog)
      @business.update!(gsc_site_url: "sc-domain:suelog.test")
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123",
        authentication_mode: "shared"
      )
    end

    test "shows google api import screen separated from csv import" do
      get admin_google_api_imports_url

      assert_response :success
      assert_includes response.body, "Google API直取得"
      assert_includes response.body, "CSV貼り付けは使いません"
      assert_includes response.body, @business.name
      assert_includes response.body, "sc-domain:suelog.test"
      assert_includes response.body, "properties/123"
      assert_includes response.body, "Google APIから取得"
      assert_includes response.body, "action=\"#{admin_google_api_imports_path}\""
      assert_includes response.body, "data-aicoo-submit-lock=\"true\""
      assert_includes response.body, "data-aicoo-loading-label=\"Google API取得中...\""
      assert_includes response.body, "aicoo-loading-feedback"
      refute_includes response.body, "action=\"#{admin_google_api_import_path(@business)}\""
      assert_includes response.body, admin_analytics_imports_path
    end

    test "runs direct google api import for a business" do
      fake_importer = Class.new do
        Result = Data.define(:metric_count, :imported_source_labels)

        def initialize(business:)
          @business = business
        end

        def call
          Result.new(2, %w[GSC GA4])
        end
      end
      original_new = AicooAnalytics::BusinessGoogleApiMetricImporter.method(:new)
      AicooAnalytics::BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |business:, **_kwargs|
        fake_importer.new(business:)
      end

      post admin_google_api_imports_url, params: { business_id: @business.id }

      assert_redirected_to admin_google_api_imports_url
      assert_equal "#{@business.name}: GSC / GA4 から直接取得しました。BusinessMetricDaily 2日分を更新しました。", flash[:notice]
    ensure
      AicooAnalytics::BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    test "shows google api error message on failure" do
      original_new = AicooAnalytics::BusinessGoogleApiMetricImporter.method(:new)
      AicooAnalytics::BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |business:, **_kwargs|
        raise AicooAnalytics::BusinessGoogleApiMetricImporter::Error, "#{business.name} GA4 Property IDが未設定です"
      end

      post admin_google_api_imports_url, params: { business_id: @business.id }

      assert_redirected_to admin_google_api_imports_url
      assert_equal "Google APIから取得できませんでした: #{@business.name} GA4 Property IDが未設定です", flash[:alert]
    ensure
      AicooAnalytics::BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end
  end
end

require "test_helper"

module Aicoo
  class BusinessGoogleConnectionSummaryTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      AnalyticsFetchRun.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
    end

    test "shows reauthentication required for invalid grant" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "#{@business.name} GA4",
        property_id: "536889590",
        enabled: true,
        authentication_mode: "shared"
      )
      setting.analytics_fetch_runs.create!(
        source_type: "ga4",
        status: "failed",
        error_message: "Google OAuth error: invalid_grant Token has been expired or revoked.",
        started_at: Time.current,
        finished_at: Time.current
      )

      summary = BusinessGoogleConnectionSummary.new(@business, source_key: "ga4").call

      assert_equal "536889590", summary.identifier
      assert_equal "AnalyticsSourceSetting", summary.setting_source
      assert summary.reauthentication_required
      assert_equal "再認証が必要", summary.status_label
    end

    test "business data source setting requires explicit credential" do
      AicooGoogleCredential.create!(
        name: "AICOO全体Google認証",
        client_id: "global-client",
        client_secret: "global-secret",
        refresh_token: "global-refresh",
        connected_at: Time.current
      )
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        enabled: true,
        connection_status: "needs_attention",
        property_identifier: "536889590",
        metadata: {
          "connection_fields" => { "property_id" => "536889590" }
        }
      )

      summary = BusinessGoogleConnectionSummary.new(@business, source_key: "ga4").call

      assert_equal "536889590", summary.identifier
      assert_equal "BusinessDataSourceSetting", summary.setting_source
      assert_nil summary.credential
      assert_equal "Google Credential未設定", summary.status_label
    end
  end
end

require "test_helper"

module Aicoo
  class BusinessGoogleDefaultLinkerTest < ActiveSupport::TestCase
    setup do
      BusinessDataSourceSetting.delete_all
      AnalyticsFetchRun.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
      AicooGoogleCredential.delete_all
      @credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      @gsc = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "AICOO GSC",
        site_url: "sc-domain:aicoo.example",
        enabled: true,
        authentication_mode: "shared",
        google_credential: @credential
      )
      @ga4 = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "AICOO GA4",
        property_id: "536889590",
        enabled: true,
        authentication_mode: "shared",
        google_credential: @credential
      )
      @business = Business.create!(
        name: "フリーランス向け請求前チェックリスト",
        description: "LP検証Business",
        status: "idea",
        created_by_aicoo: true,
        lifecycle_stage: "lp_validation",
        business_type: "landing_page"
      )
    end

    test "links aicoo internal business to global ga4 and gsc settings" do
      result = BusinessGoogleDefaultLinker.call(@business)

      assert_equal 2, result.linked_count
      ga4_setting = @business.business_data_source_settings.find_by!(source_key: "ga4")
      gsc_setting = @business.business_data_source_settings.find_by!(source_key: "gsc")
      assert_equal "536889590", ga4_setting.connection_field_value("property_id")
      assert_equal "sc-domain:aicoo.example", gsc_setting.connection_field_value("site_url")
      assert_equal "1", ga4_setting.metadata.dig("source_binding", "use_global")
      assert_equal "1", gsc_setting.metadata.dig("source_binding", "use_global")
      assert_equal @ga4.id, ga4_setting.metadata["inherited_analytics_source_setting_id"]
      assert_equal @gsc.id, gsc_setting.metadata["inherited_analytics_source_setting_id"]
      assert_equal @credential.id, ga4_setting.metadata["google_credential_id"]
      assert_equal "linked", ga4_setting.connection_status
    end

    test "does not overwrite existing business specific google setting" do
      @business.business_data_source_settings.create!(
        source_key: "ga4",
        enabled: true,
        connection_status: "linked",
        property_identifier: "properties/999",
        metadata: {
          "connection_fields" => { "property_id" => "properties/999" },
          "source_binding" => { "use_global" => "0" }
        }
      )

      result = BusinessGoogleDefaultLinker.call(@business)

      assert_equal "already_business_configured", result.skipped_sources["ga4"]
      assert_equal "properties/999", @business.business_data_source_settings.find_by!(source_key: "ga4").connection_field_value("property_id")
      assert_equal "sc-domain:aicoo.example", @business.business_data_source_settings.find_by!(source_key: "gsc").connection_field_value("site_url")
    end

    test "skips non aicoo businesses" do
      suelog = businesses(:suelog)

      result = BusinessGoogleDefaultLinker.call(suelog)

      assert_equal "business_not_eligible", result.skipped_sources["ga4"]
      assert_nil suelog.business_data_source_settings.find_by(source_key: "ga4")
    end
  end
end

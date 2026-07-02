require "test_helper"

module Aicoo
  class BusinessConnectionStatusTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      DataSourceCostProfile.ensure_defaults!
      BusinessDataSourceSetting.delete_all
      AnalyticsFetchRun.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
      AicooGoogleCredential.delete_all
    end

    test "ga4 is configured via global setting when default google credential is connected" do
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )

      status = BusinessConnectionStatus.new(@business, source_key: "ga4").call

      assert status.configured?
      assert_equal "global", status.status_key
      assert_equal "設定済み", status.status_label
      assert_equal "全体設定を使用", status.setting_label
      assert_equal "設定済み（全体設定を使用）", status.display_label
    end

    test "ga4 is configured via business setting when property and credential are set" do
      credential = AicooGoogleCredential.create!(
        name: "吸えログGoogle認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        connection_status: "linked",
        property_identifier: "536889590",
        metadata: {
          "google_credential_id" => credential.id,
          "source_binding" => { "use_global" => "0" },
          "connection_fields" => { "property_id" => "536889590" }
        }
      )

      status = BusinessConnectionStatus.new(@business, source_key: "ga4").call

      assert status.configured?
      assert_equal "business", status.status_key
      assert_equal "設定済み", status.status_label
      assert_equal "Business個別設定", status.setting_label
      assert_equal "536889590", status.identifier
      assert_equal credential, status.credential
    end

    test "ga4 is missing when neither business nor global setting is usable" do
      status = BusinessConnectionStatus.new(@business, source_key: "ga4").call

      refute status.configured?
      assert_equal "missing", status.status_key
      assert_equal "未設定", status.status_label
      assert_equal "未設定", status.setting_label
    end

    test "serp is configured via global serp api key" do
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "serper-key")

      status = BusinessConnectionStatus.new(@business, source_key: "serp").call

      assert status.configured?
      assert_equal "global", status.status_key
      assert_equal "設定済み（全体設定を使用）", status.display_label
    end

    test "openai is configured via env api key" do
      original = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "openai-key"
      DataSourceCostProfile.find_by!(source_key: "openai").update!(api_key: nil)

      status = BusinessConnectionStatus.new(@business, source_key: "openai").call

      assert status.configured?
      assert_equal "global", status.status_key
      assert_equal "設定済み（全体設定を使用）", status.display_label
    ensure
      original.nil? ? ENV.delete("OPENAI_API_KEY") : ENV["OPENAI_API_KEY"] = original
    end
  end
end

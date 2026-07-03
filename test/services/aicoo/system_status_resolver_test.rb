require "test_helper"

module Aicoo
  class SystemStatusResolverTest < ActiveSupport::TestCase
    test "returns four-level status for business google sources" do
      business = businesses(:suelog)

      status = SystemStatusResolver.call("ga4", business:)

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "GA4", status.label
      assert status.reason.present?
      assert status.detail_url.present?
    end

    test "uses global google credential when business has no individual setting" do
      business = businesses(:suelog)
      create_google_credential!

      status = SystemStatusResolver.call("ga4", business:)

      assert_equal "CONNECTED", status.status
      assert_equal "全体設定を使用", status.source
      assert_equal "設定済み（全体設定を使用）", status.display_label
    end

    test "uses business google source setting with global credential fallback" do
      business = businesses(:suelog)
      credential = create_google_credential!
      business.business_data_source_settings.create!(
        source_key: "ga4",
        connection_status: "linked",
        metadata: { "connection_fields" => { "property_id" => "536889590" } }
      )

      status = SystemStatusResolver.call("ga4", business:)

      assert_equal "CONNECTED", status.status
      assert_equal "Business個別設定", status.source
      assert_equal credential.id, status.metadata[:credential_id]
      assert_equal "536889590", status.metadata[:property_id]
      assert_equal "設定済み（Business個別設定）", status.display_label
    end

    test "oauth expiration is broken with reauthentication next action" do
      business = businesses(:suelog)
      create_google_credential!(token_expires_at: 1.hour.ago)

      status = SystemStatusResolver.call("gsc", business:)

      assert_equal "BROKEN", status.status
      assert_match(/再認証/, status.reason)
      assert_equal "Google再認証", status.next_action
    end

    test "missing ga4 property and missing global credential is not configured" do
      business = businesses(:suelog)

      status = SystemStatusResolver.call("ga4", business:)

      assert_equal "NOT_CONFIGURED", status.status
      assert_match(/Google全体設定がありません|未設定/, status.reason)
      assert_equal "Business設定を開く", status.next_action
    end

    test "missing gsc site and missing global credential is not configured" do
      business = businesses(:suelog)

      status = SystemStatusResolver.call("gsc", business:)

      assert_equal "NOT_CONFIGURED", status.status
      assert_match(/Google全体設定がありません|未設定/, status.reason)
      assert_equal "Business設定を開く", status.next_action
    end

    test "permission denied fetch error is broken with concrete reason" do
      business = businesses(:suelog)
      credential = create_google_credential!
      site = AicooAnalyticsSite.create!(
        business:,
        name: "Resolver permission site",
        public_url: "https://resolver-permission.example.com",
        domain: "resolver-permission.example.com",
        ga4_property_id: "536889590",
        authentication_mode: "shared"
      )
      setting = site.ga4_setting
      setting.update!(google_credential: credential)
      setting.analytics_fetch_runs.create!(
        source_type: "ga4",
        status: "failed",
        error_message: "PERMISSION_DENIED: property access denied",
        started_at: Time.current,
        finished_at: Time.current
      )

      status = SystemStatusResolver.call("ga4", business:)

      assert_equal "BROKEN", status.status
      assert_match(/PERMISSION_DENIED/, status.reason)
      assert_equal "Business設定を開く", status.next_action
    end

    test "returns daily run status from shared execution resolver" do
      status = SystemStatusResolver.call("daily_run")

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "Daily Run", status.label
      assert status.reason.present?
    end

    test "returns traffic serp status from serp run summary" do
      status = SystemStatusResolver.call("traffic_serp")

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "SERP", status.label
      assert_match(/今日/, status.reason)
      assert_equal "SerpRun", status.source
    end

    private

    def create_google_credential!(attributes = {})
      AicooGoogleCredential.create!(
        {
          name: "Resolver Google #{SecureRandom.hex(4)}",
          client_id: "client-#{SecureRandom.hex(4)}",
          client_secret: "secret",
          refresh_token: "refresh-token",
          connected_at: Time.current
        }.merge(attributes)
      )
    end
  end
end

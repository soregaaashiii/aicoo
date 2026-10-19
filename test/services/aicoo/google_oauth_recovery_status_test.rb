require "test_helper"

module Aicoo
  class GoogleOauthRecoveryStatusTest < ActiveSupport::TestCase
    test "marks invalid_grant when latest source run has revoked token error" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "吸えログ GA4",
        property_id: "536889590",
        enabled: true,
        google_credential: credential
      )
      setting.analytics_fetch_runs.create!(
        source_type: "ga4",
        status: "failed",
        error_message: "invalid_grant Token has been expired or revoked.",
        started_at: Time.current,
        finished_at: Time.current
      )

      ga4 = GoogleOauthRecoveryStatus.new(credential:).call.find { |status| status.source_key == "ga4" }

      assert_equal "invalid_grant", ga4.status
      assert_predicate ga4, :invalid_grant?
      assert_includes ga4.last_error, "invalid_grant"
    end

    test "marks missing when refresh token is absent" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret"
      )

      statuses = GoogleOauthRecoveryStatus.new(credential:).call

      assert_equal %w[missing missing], statuses.map(&:status)
    end

    test "newer successful fetch supersedes an older invalid grant" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "吸えログ GSC",
        site_url: "sc-domain:suelog.jp",
        enabled: true,
        google_credential: credential
      )
      setting.analytics_fetch_runs.create!(
        source_type: "gsc",
        status: "failed",
        error_message: "invalid_grant Token has been expired or revoked.",
        started_at: 2.minutes.ago,
        finished_at: 2.minutes.ago
      )
      setting.analytics_fetch_runs.create!(
        source_type: "gsc",
        status: "success",
        snapshot_count: 28,
        started_at: 1.minute.ago,
        finished_at: 1.minute.ago
      )

      gsc = GoogleOauthRecoveryStatus.new(credential:).call.find { |status| status.source_key == "gsc" }

      assert_equal "connected", gsc.status
      assert_predicate gsc, :connected?
      assert_nil gsc.last_error
      assert gsc.last_success_at.present?
    end
  end
end

require "test_helper"

module Aicoo
  class DataSourceSettingsPresenterTest < ActiveSupport::TestCase
    setup do
      DataSourceCostProfile.ensure_defaults!
      @business = businesses(:suelog)
    end

    test "serp is manual by default" do
      status = DataSourceSettingsPresenter.new.global_statuses.find { |item| item.source_key == "serp" }

      assert_equal "manual", status.execution_mode
      assert status.manual_paid
    end

    test "business uses global setting when global credentials are configured" do
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "secret")

      status = DataSourceSettingsPresenter.new.business_status(@business, "serp")

      assert_equal "global", status.status_key
      assert_equal "設定済み（全体設定を使用）", status.status_label
      assert status.uses_global
    end

    test "business status is individual when linked" do
      credential = AicooGoogleCredential.create!(
        name: "吸えログGoogle認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        connection_status: "linked",
        property_identifier: "properties/123",
        metadata: {
          "google_credential_id" => credential.id,
          "source_binding" => { "use_global" => false },
          "connection_fields" => { "property_id" => "properties/123" }
        }
      )

      status = DataSourceSettingsPresenter.new.business_status(@business, "ga4")

      assert_equal "business", status.status_key
      assert_equal "設定済み（Business個別設定）", status.status_label
      assert_not status.uses_global
    end

    test "business ga4 status uses analytics site property id with global setting" do
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
        ga4_property_id: "properties/999",
        authentication_mode: "shared"
      )

      status = DataSourceSettingsPresenter.new.business_status(@business, "ga4")

      assert_equal "global", status.status_key
      assert_equal "設定済み（全体設定を使用）", status.status_label
      assert_equal "properties/999", status.connection_summary
    end

    test "business ga4 status uses business named setting with global credential" do
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "#{@business.name} GA4",
        property_id: "536889590",
        enabled: true,
        authentication_mode: "shared"
      )

      status = DataSourceSettingsPresenter.new.business_status(@business, "ga4")

      assert_equal "global", status.status_key
      assert_equal "設定済み（全体設定を使用）", status.status_label
      assert_equal "536889590", status.connection_summary
    end

    test "business status is missing when global and individual are absent" do
      status = DataSourceSettingsPresenter.new.business_status(@business, "x")

      assert_equal "missing", status.status_key
      assert_equal "未設定（未設定）", status.status_label
      assert_equal "critical", status.status_level
    end

    test "openai global status uses OPENAI_API_KEY env" do
      original = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "env-openai-key"
      DataSourceCostProfile.find_by!(source_key: "openai").update!(api_key: nil)

      status = DataSourceSettingsPresenter.new.global_statuses.find { |item| item.source_key == "openai" }

      assert_equal "connected", status.status_key
      assert_equal "✅ Connected", status.status_label
      assert status.global_default_available
    ensure
      ENV["OPENAI_API_KEY"] = original
    end

    test "codex status is individual when business project fields are configured" do
      @business.update!(
        project_key: "suelog",
        local_project_path: "/apps/suelog",
        repository_name: "suelog"
      )

      status = DataSourceSettingsPresenter.new.codex_status(@business)

      assert_equal "business", status.status_key
      assert_equal "設定済み（Business個別設定）", status.status_label
    end

    test "codex status is internal for aicoo created business" do
      @business.update!(created_by_aicoo: true, project_key: nil, local_project_path: nil, repository_name: nil)

      status = DataSourceSettingsPresenter.new.codex_status(@business)

      assert_equal "aicoo_internal", status.status_key
      assert_equal "設定済み（Business個別設定）", status.status_label
      assert_equal "healthy", status.status_level
      assert_equal "AICOO内部プロジェクト（接続済み）", status.summary
    end
  end
end

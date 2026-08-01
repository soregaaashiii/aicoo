require "test_helper"
require Rails.root.join("db/migrate/20260801090000_consolidate_cloudflare_connection_settings")

class ConsolidateCloudflareConnectionSettingsTest < ActiveSupport::TestCase
  test "moves legacy business credentials to the global profile and preserves project selection" do
    business = Business.create!(name: "Cloudflare移行事業", status: "launched")
    setting = BusinessDataSourceSetting.create!(
      business:,
      source_key: "cloudflare_pages",
      metadata: {
        "account_id" => "legacy-account",
        "api_token" => "legacy-token",
        "project_name" => "legacy-project",
        "production_url" => "https://legacy.example.com"
      }
    )

    ConsolidateCloudflareConnectionSettings.new.migrate(:up)

    profile = DataSourceCostProfile.find_by!(source_key: "cloudflare_pages")
    assert_equal "legacy-account", profile.credentials["account_id"]
    assert_equal "legacy-token", profile.credentials["api_token"]
    setting.reload
    assert_equal "legacy-project", setting.property_identifier
    assert_equal "https://legacy.example.com", setting.endpoint_url
    assert_equal({ "use_global" => "1" }, setting.metadata["source_binding"])
    assert_nil setting.metadata["account_id"]
    assert_nil setting.metadata["api_token"]
  end
end

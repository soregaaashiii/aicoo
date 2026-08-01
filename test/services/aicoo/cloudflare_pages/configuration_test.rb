require "test_helper"

module Aicoo
  module CloudflarePages
    class ConfigurationTest < ActiveSupport::TestCase
      test "uses cloudflare environment values first" do
        profile = DataSourceCostProfile.new(
          source_key: "cloudflare_pages",
          name: "Cloudflare Pages",
          metadata: {
            "credentials" => {
              "account_id" => "stored-account",
              "api_token" => "stored-token",
              "project_name" => "stored-project"
            }
          }
        )
        configuration = Configuration.new(
          env: {
            "CLOUDFLARE_ACCOUNT_ID" => "env-account",
            "CLOUDFLARE_API_TOKEN" => "env-token",
            "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
          },
          profile:
        )

        assert_equal "env-account", configuration.account_id
        assert_equal "env-token", configuration.api_token
        assert_equal "aicoo-lp", configuration.project_name
        assert_equal "https://aicoo-lp.pages.dev", configuration.production_url
      end

      test "uses settings profile when cloudflare environment values are absent" do
        profile = DataSourceCostProfile.new(
          source_key: "cloudflare_pages",
          name: "Cloudflare Pages",
          metadata: {
            "credentials" => {
              "account_id" => "stored-account",
              "api_token" => "stored-token",
              "project_name" => "stored-project"
            }
          }
        )
        configuration = Configuration.new(env: {}, profile:)

        assert_equal "stored-account", configuration.account_id
        assert_equal "stored-token", configuration.api_token
        assert_equal "stored-project", configuration.project_name
      end

      test "uses global authentication and business specific project and domain" do
        business = Business.create!(name: "Cloudflare選択事業", status: "launched")
        profile = DataSourceCostProfile.create!(
          source_key: "cloudflare_pages",
          name: "Cloudflare Pages",
          metadata: {
            "credentials" => { "account_id" => "global-account", "access_token" => "oauth-token" },
            "cloudflare" => {
              "status" => "connected",
              "projects" => [
                {
                  "name" => "business-pages",
                  "production_url" => "https://business-pages.pages.dev",
                  "domains" => [ "lp.example.com" ]
                }
              ]
            }
          }
        )
        BusinessDataSourceSetting.create!(
          business:,
          source_key: "cloudflare_pages",
          property_identifier: "business-pages",
          endpoint_url: "https://lp.example.com",
          connection_status: "linked"
        )

        configuration = Configuration.new(env: {}, profile:, business:)

        assert_equal "global-account", configuration.account_id
        assert_equal "oauth-token", configuration.api_token
        assert_equal "business-pages", configuration.project_name
        assert_equal "https://lp.example.com", configuration.production_url
        assert_equal [ "lp.example.com" ], configuration.available_domains
      end

      test "keeps the existing default project for businesses without a selection" do
        business = Business.create!(name: "既存Cloudflare事業", status: "launched")
        configuration = Configuration.new(env: {}, business:)

        assert_equal "aicoo-lp", configuration.project_name
        assert_equal "https://aicoo-lp.pages.dev", configuration.production_url
      end
    end
  end
end

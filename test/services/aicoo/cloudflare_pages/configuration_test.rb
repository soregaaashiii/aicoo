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
    end
  end
end

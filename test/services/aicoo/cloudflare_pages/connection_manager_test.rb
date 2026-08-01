require "test_helper"

module Aicoo
  module CloudflarePages
    class ConnectionManagerTest < ActiveSupport::TestCase
      test "stores one global api connection and pages project snapshots" do
        fake_client = Class.new do
          def initialize(account_id: nil, token:)
            @account_id = account_id
            @token = token
          end

          def project_snapshots(account_id:)
            raise "unexpected account" unless account_id == "account-1"
            raise "unexpected token" unless @token == "token-1"

            [ { "name" => "aicoo-lp", "production_url" => "https://aicoo-lp.pages.dev", "domains" => [] } ]
          end
        end
        manager = ConnectionManager.new(env: {}, api_client_class: fake_client)

        result = manager.connect_with_api_token!(account_id: "account-1", api_token: "token-1")

        assert result.connected?
        profile = DataSourceCostProfile.find_by!(source_key: "cloudflare_pages")
        assert_equal "account-1", profile.credentials["account_id"]
        assert_equal "token-1", profile.credentials["api_token"]
        assert_equal "connected", profile.metadata.dig("cloudflare", "status")
        assert_equal "aicoo-lp", profile.metadata.dig("cloudflare", "projects", 0, "name")
        assert_nil profile.credentials["project_name"]
      end

      test "records a connection error without creating business credentials" do
        fake_client = Class.new do
          def initialize(account_id: nil, token:); end
          def project_snapshots(account_id:)
            raise ApiClient::Error, "token expired"
          end
        end
        manager = ConnectionManager.new(env: {}, api_client_class: fake_client)

        assert_raises(ApiClient::Error) do
          manager.connect_with_api_token!(account_id: "account-1", api_token: "bad")
        end

        profile = DataSourceCostProfile.find_by!(source_key: "cloudflare_pages")
        assert_equal "error", profile.metadata.dig("cloudflare", "status")
        assert_equal "token expired", profile.last_error
        assert_equal 0, BusinessDataSourceSetting.where(source_key: "cloudflare_pages").count
      end

      test "successful test stores the refreshed projects and clears the previous error" do
        calls = 0
        fake_client = Class.new do
          define_method(:initialize) do |account_id: nil, token:|
            @account_id = account_id
            @token = token
          end

          define_method(:project_snapshots) do |account_id:|
            calls += 1
            raise "unexpected account" unless account_id == "account-1"
            raise "unexpected token" unless @token == "token-1"

            [ { "name" => "aicoo-lp", "production_url" => "https://aicoo-lp.pages.dev", "domains" => [] } ]
          end
        end
        profile = DataSourceCostProfile.create!(
          source_key: "cloudflare_pages",
          name: "Cloudflare Pages",
          execution_mode: "auto",
          enabled: true,
          last_error: "old error",
          metadata: {
            "credentials" => { "account_id" => "account-1", "api_token" => "token-1" },
            "cloudflare" => { "status" => "error", "last_error" => "old error", "use_stored_credentials" => true }
          }
        )

        result = ConnectionManager.new(profile:, env: {}, api_client_class: fake_client).test!

        profile.reload
        assert result.connected?
        assert_equal 1, calls
        assert_equal "connected", profile.metadata.dig("cloudflare", "status")
        assert_equal "aicoo-lp", profile.metadata.dig("cloudflare", "projects", 0, "name")
        assert_nil profile.metadata.dig("cloudflare", "last_error")
        assert_nil profile.last_error
      end

      test "stores oauth credentials globally and resolves the account" do
        fake_client = Class.new do
          def initialize(account_id: nil, token:)
            @account_id = account_id
            @token = token
          end

          def accounts
            raise "unexpected token" unless @token == "oauth-token"

            [ { "id" => "oauth-account" } ]
          end

          def project_snapshots(account_id:)
            raise "unexpected account" unless account_id == "oauth-account"

            []
          end
        end
        token = OauthClient::Token.new(
          access_token: "oauth-token",
          refresh_token: "refresh-token",
          expires_at: 1.hour.from_now,
          scope: "pages:read pages:write"
        )

        result = ConnectionManager.new(env: {}, api_client_class: fake_client).connect_with_oauth!(token:)

        assert result.connected?
        profile = DataSourceCostProfile.find_by!(source_key: "cloudflare_pages")
        assert_equal "oauth-account", profile.credentials["account_id"]
        assert_equal "oauth-token", profile.credentials["access_token"]
        assert_equal "refresh-token", profile.credentials["refresh_token"]
        assert_equal "oauth", profile.metadata.dig("cloudflare", "authentication_mode")
        assert_nil profile.credentials["api_token"]
      end

      test "creates a github connected pages project and refreshes snapshots" do
        calls = []
        fake_client = Class.new do
          define_method(:initialize) do |account_id: nil, token:|
            @account_id = account_id
            @token = token
          end

          define_method(:create_project) do |**values|
            calls << values.merge(account_id: @account_id, token: @token)
          end

          def project_snapshots(account_id:)
            [ { "name" => "new-pages", "production_url" => "https://new-pages.pages.dev", "domains" => [] } ]
          end
        end
        profile = DataSourceCostProfile.create!(
          source_key: "cloudflare_pages",
          name: "Cloudflare Pages",
          metadata: {
            "credentials" => { "account_id" => "account-1", "api_token" => "token-1" },
            "cloudflare" => { "use_stored_credentials" => true, "status" => "connected" }
          }
        )

        ConnectionManager.new(profile:, env: {}, api_client_class: fake_client).create_project!(
          name: "new-pages",
          production_branch: "main"
        )

        call = calls.fetch(0)
        assert_equal "new-pages", call[:name]
        assert_equal "main", call[:production_branch]
        assert_equal "github", call.dig(:source, :type)
        assert_equal "soregaaashiii", call.dig(:source, :config, :owner)
        assert_equal "aicoo-lp", call.dig(:source, :config, :repo_name)
        assert_equal "new-pages", profile.reload.metadata.dig("cloudflare", "projects", 0, "name")
      end
    end
  end
end

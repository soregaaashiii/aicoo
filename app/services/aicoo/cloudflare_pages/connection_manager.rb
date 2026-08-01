require "uri"

module Aicoo
  module CloudflarePages
    class ConnectionManager
      Result = Data.define(:status, :account_id, :projects, :connected_at, :error) do
        def connected? = status == "connected"
      end

      def initialize(profile: nil, env: ENV, api_client_class: ApiClient)
        @profile = profile
        @env = env
        @api_client_class = api_client_class
      end

      def configuration
        @configuration ||= Configuration.new(env:, profile:)
      end

      def status
        configuration.connection_status
      end

      def connected?
        status == "connected" && configuration.globally_connected?
      end

      def oauth_available?
        OauthClient.new(env:).configured?
      end

      def connect_with_api_token!(account_id:, api_token:)
        values = profile.credentials.to_h.merge(
          "account_id" => account_id.presence || profile.credentials.to_h["account_id"],
          "api_token" => api_token.presence || profile.credentials.to_h["api_token"]
        ).compact
        values.except!("access_token", "refresh_token", "token_expires_at", "oauth_scope")
        persist_credentials!(values, authentication_mode: "api_token")
        test!
      end

      def connect_with_oauth!(token:)
        values = profile.credentials.to_h.except("api_token").merge(
          "access_token" => token.access_token,
          "refresh_token" => token.refresh_token,
          "token_expires_at" => token.expires_at&.iso8601,
          "oauth_scope" => token.scope
        ).compact
        persist_credentials!(values, authentication_mode: "oauth")
        test!
      end

      def test!
        account_id = configuration.account_id.presence || resolve_account_id!
        client = api_client_class.new(account_id:, token: configuration.api_token)
        projects = client.project_snapshots(account_id:)
        record_success!(account_id:, projects:)
      rescue ApiClient::Error => e
        record_failure!(e.message)
        raise
      end

      def create_project!(name:, production_branch: "main")
        raise ApiClient::Error, "Pages Project名を入力してください。" if name.blank?

        account_id = configuration.account_id.presence || resolve_account_id!
        api_client_class.new(account_id:, token: configuration.api_token).create_project(
          name:,
          production_branch:,
          source: github_source(production_branch:)
        )
        test!
      rescue ApiClient::Error => e
        record_failure!(e.message)
        raise
      end

      private

      attr_reader :env, :api_client_class

      def profile
        @profile ||= DataSourceCostProfile.find_or_initialize_by(source_key: Configuration::PROFILE_KEY) do |record|
          record.name = "Cloudflare Pages"
          record.execution_mode = "auto"
          record.enabled = true
        end
      end

      def resolve_account_id!
        accounts = api_client_class.new(token: configuration.api_token).accounts
        account_id = accounts.first.to_h["id"].presence
        raise ApiClient::Error, "接続可能なCloudflare Accountがありません。" if account_id.blank?

        account_id
      end

      def github_source(production_branch:)
        path = URI.parse(configuration.repository_url).path.delete_prefix("/").delete_suffix(".git")
        owner, repository = path.split("/", 2)
        return if owner.blank? || repository.blank?

        {
          type: "github",
          config: {
            owner:,
            repo_name: repository,
            production_branch:,
            deployments_enabled: true,
            pr_comments_enabled: false
          }
        }
      rescue URI::InvalidURIError
        nil
      end

      def persist_credentials!(credentials, authentication_mode:)
        cloudflare = profile.metadata.to_h.fetch("cloudflare", {}).merge(
          "authentication_mode" => authentication_mode,
          "use_stored_credentials" => true,
          "status" => "connecting",
          "last_error" => nil
        )
        profile.update!(
          name: "Cloudflare Pages",
          execution_mode: "auto",
          enabled: true,
          last_error: nil,
          metadata: profile.metadata.to_h.merge(
            "credentials" => credentials,
            "cloudflare" => cloudflare
          )
        )
        @configuration = nil
      end

      def record_success!(account_id:, projects:)
        now = Time.current
        credentials = profile.credentials.to_h.merge("account_id" => account_id)
        cloudflare = profile.metadata.to_h.fetch("cloudflare", {}).merge(
          "status" => "connected",
          "last_connected_at" => now.iso8601,
          "last_tested_at" => now.iso8601,
          "last_error" => nil,
          "projects" => projects
        )
        cloudflare["default_project_name"] ||= credentials.delete("project_name").presence || Configuration::DEFAULT_PROJECT_NAME
        profile.update!(
          name: "Cloudflare Pages",
          execution_mode: "auto",
          enabled: true,
          last_run_at: now,
          last_error: nil,
          metadata: profile.metadata.to_h.merge(
            "credentials" => credentials,
            "cloudflare" => cloudflare
          )
        )
        @configuration = nil
        Result.new(status: "connected", account_id:, projects:, connected_at: now, error: nil)
      end

      def record_failure!(message)
        now = Time.current
        cloudflare = profile.metadata.to_h.fetch("cloudflare", {}).merge(
          "status" => "error",
          "last_tested_at" => now.iso8601,
          "last_error" => message
        )
        profile.update!(
          last_run_at: now,
          last_error: message,
          metadata: profile.metadata.to_h.merge("cloudflare" => cloudflare)
        )
        @configuration = nil
      end
    end
  end
end

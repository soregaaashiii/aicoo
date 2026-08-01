module Aicoo
  module CloudflarePages
    class Configuration
      PROFILE_KEY = "cloudflare_pages".freeze
      DEFAULT_PROJECT_NAME = "aicoo-lp".freeze
      DEFAULT_REPOSITORY_URL = "https://github.com/soregaaashiii/aicoo-lp".freeze
      DEFAULT_BRANCH = "main".freeze

      def initialize(env: ENV, profile: nil, business: nil, business_setting: nil)
        @env = env
        @profile = profile
        @business = business
        @business_setting = business_setting
      end

      def account_id
        return credential("account_id") if stored_credentials_preferred?

        env["CLOUDFLARE_ACCOUNT_ID"].presence || credential("account_id")
      end

      def api_token
        stored = credential("access_token").presence || credential("api_token")
        return stored if stored_credentials_preferred?

        env["CLOUDFLARE_API_TOKEN"].presence || stored
      end

      def project_name
        business_setting&.property_identifier.presence ||
          env["CLOUDFLARE_PROJECT_NAME"].presence ||
          profile&.metadata.to_h&.dig("cloudflare", "default_project_name").presence ||
          credential("project_name").presence ||
          DEFAULT_PROJECT_NAME
      end

      def repository_url
        env["AICOO_LP_GITHUB_REPOSITORY"].presence || DEFAULT_REPOSITORY_URL
      end

      def branch
        env["AICOO_LP_GITHUB_BRANCH"].presence || DEFAULT_BRANCH
      end

      def production_url
        business_setting&.endpoint_url.presence ||
          project_snapshot&.dig("production_url").presence ||
          env["CLOUDFLARE_PAGES_PRODUCTION_URL"].presence ||
          "https://#{project_name}.pages.dev"
      end

      def github_token
        env["AICOO_GITHUB_TOKEN"].presence || env["GITHUB_TOKEN"].presence || env["GH_TOKEN"].presence
      end

      def cloudflare_api_configured?
        account_id.present? && api_token.present? && project_name.present?
      end

      def globally_connected?
        account_id.present? && api_token.present?
      end

      def connection_status
        stored = profile&.metadata.to_h&.dig("cloudflare", "status").presence
        return "error" if stored == "error"
        return "connected" if globally_connected? && stored.in?([ nil, "disconnected" ])
        return stored if stored

        globally_connected? ? "connected" : "disconnected"
      end

      def connection_error
        profile&.last_error.presence || profile&.metadata.to_h&.dig("cloudflare", "last_error").presence
      end

      def last_connected_at
        value = profile&.metadata.to_h&.dig("cloudflare", "last_connected_at").presence || profile&.last_run_at
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        value
      end

      def authentication_mode
        profile&.metadata.to_h&.dig("cloudflare", "authentication_mode").presence ||
          (credential("access_token").present? ? "oauth" : "api_token")
      end

      def oauth_refresh_token
        credential("refresh_token")
      end

      def oauth_token_expires_at
        value = credential("token_expires_at").presence
        Time.zone.parse(value.to_s) if value
      rescue ArgumentError
        nil
      end

      def available_projects
        Array(profile&.metadata.to_h&.dig("cloudflare", "projects")).map(&:to_h)
      end

      def available_domains(project = project_name)
        snapshot = project_snapshot_for(project)
        Array(snapshot&.dig("domains")).compact
      end

      def project_snapshot_for(name)
        available_projects.find { |project| project["name"] == name.to_s }
      end

      def business_setting
        return @business_setting unless @business_setting.nil?
        return unless @business

        @business_setting = BusinessDataSourceSetting.for_business_and_source(@business, PROFILE_KEY)
      end

      def for_business(business)
        self.class.new(env:, profile:, business:)
      end

      def github_configured?
        github_token.present? && repository_url.present?
      end

      private

      attr_reader :env

      def profile
        @profile ||= DataSourceCostProfile.find_by(source_key: PROFILE_KEY)
      end

      def credential(key)
        profile&.credentials.to_h&.dig(key)
      end

      def project_snapshot
        project_snapshot_for(project_name)
      end

      def stored_credentials_preferred?
        profile&.metadata.to_h&.dig("cloudflare", "use_stored_credentials") == true
      end
    end
  end
end

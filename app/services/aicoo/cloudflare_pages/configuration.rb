module Aicoo
  module CloudflarePages
    class Configuration
      PROFILE_KEY = "cloudflare_pages".freeze
      DEFAULT_PROJECT_NAME = "aicoo-lp".freeze
      DEFAULT_REPOSITORY_URL = "https://github.com/soregaaashiii/aicoo-lp".freeze
      DEFAULT_BRANCH = "main".freeze

      def initialize(env: ENV, profile: nil)
        @env = env
        @profile = profile
      end

      def account_id
        env["CLOUDFLARE_ACCOUNT_ID"].presence || credential("account_id")
      end

      def api_token
        env["CLOUDFLARE_API_TOKEN"].presence || credential("api_token")
      end

      def project_name
        env["CLOUDFLARE_PROJECT_NAME"].presence || credential("project_name").presence || DEFAULT_PROJECT_NAME
      end

      def repository_url
        env["AICOO_LP_GITHUB_REPOSITORY"].presence || DEFAULT_REPOSITORY_URL
      end

      def branch
        env["AICOO_LP_GITHUB_BRANCH"].presence || DEFAULT_BRANCH
      end

      def production_url
        env["CLOUDFLARE_PAGES_PRODUCTION_URL"].presence || "https://#{project_name}.pages.dev"
      end

      def github_token
        env["AICOO_GITHUB_TOKEN"].presence || env["GITHUB_TOKEN"].presence || env["GH_TOKEN"].presence
      end

      def cloudflare_api_configured?
        account_id.present? && api_token.present? && project_name.present?
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
    end
  end
end

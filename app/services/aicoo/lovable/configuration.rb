module Aicoo
  module Lovable
    class Configuration
      DEFAULT_MCP_URL = "https://mcp.lovable.dev".freeze
      DEFAULT_BUILD_URL = "https://lovable.dev/".freeze

      attr_reader :env

      def initialize(env: ENV)
        @env = env
      end

      def mcp_url
        env["LOVABLE_MCP_URL"].presence || DEFAULT_MCP_URL
      end

      def access_token
        env["LOVABLE_MCP_ACCESS_TOKEN"].presence || env["LOVABLE_ACCESS_TOKEN"].presence
      end

      def workspace_id
        env["LOVABLE_WORKSPACE_ID"].presence
      end

      def build_url
        env["LOVABLE_BUILD_URL"].presence || DEFAULT_BUILD_URL
      end

      def open_timeout
        positive_integer(env["LOVABLE_OPEN_TIMEOUT"], 10)
      end

      def read_timeout
        positive_integer(env["LOVABLE_READ_TIMEOUT"], 300)
      end

      def configured?
        access_token.present?
      end

      def connection_mode
        "build_url"
      end

      def diagnostic_snapshot
        {
          "connection_mode" => connection_mode,
          "mcp_url" => mcp_url,
          "workspace_id_configured" => workspace_id.present?,
          "access_token_configured" => access_token.present?,
          "build_url" => build_url,
          "official_launch_route" => "build_with_url"
        }
      end

      private

      def positive_integer(value, fallback)
        parsed = value.to_i
        parsed.positive? ? parsed : fallback
      end
    end
  end
end

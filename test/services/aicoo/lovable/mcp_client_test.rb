require "test_helper"

module Aicoo
  module Lovable
    class McpClientTest < ActiveSupport::TestCase
      test "initializes MCP and creates a project with the documented arguments" do
        requests = []
        transport = lambda do |payload, session_id:, notification:|
          requests << [ payload, session_id, notification ]
          case payload["method"]
          when "initialize"
            { "result" => { "protocolVersion" => "2025-03-26" } }
          when "notifications/initialized"
            {}
          when "tools/call"
            {
              "result" => {
                "structuredContent" => {
                  "project_id" => "project-1",
                  "preview_url" => "https://project-1.lovable.app"
                }
              }
            }
          end
        end
        configuration = Configuration.new(env: {
          "LOVABLE_MCP_ACCESS_TOKEN" => "secret-token",
          "LOVABLE_WORKSPACE_ID" => "workspace-1"
        })
        client = McpClient.new(configuration:, transport:)

        result = client.create_project(description: "Test LP", initial_message: "Build it")

        assert_equal "project-1", result["project_id"]
        tool_request = requests.find { |request, _session, _notification| request["method"] == "tools/call" }.first
        assert_equal "create_project", tool_request.dig("params", "name")
        assert_equal "workspace-1", tool_request.dig("params", "arguments", "workspace_id")
        assert_equal "Build it", tool_request.dig("params", "arguments", "initial_message")
        assert_equal "private", tool_request.dig("params", "arguments", "visibility")
      end

      test "uses Build URL without exposing a secret when MCP is not configured" do
        configuration = Configuration.new(env: {})

        assert_not configuration.configured?
        assert_equal "build_url", configuration.connection_mode
        url = BuildUrl.call("吸えログのLPを作る", base_url: configuration.build_url)
        assert_includes url, "autosubmit=true"
        assert_includes url, "prompt="
        assert_not_includes url, "secret"
      end
    end
  end
end

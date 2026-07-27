require "test_helper"

module Aicoo
  module Lovable
    class BuildWithUrlLauncherTest < ActiveSupport::TestCase
      test "creates the documented autosubmit URL with encoded prompt and public images" do
        launcher = BuildWithUrlLauncher.new(configuration: Configuration.new(env: {}))

        result = launcher.call(
          prompt: "吸えログのLPを作る",
          image_urls: [ "https://example.com/logo.png", "not-a-url" ]
        )

        assert_equal "build_with_url", result.launcher_name
        assert_equal 1, result.image_count
        assert_includes result.url, "https://lovable.dev/?autosubmit=true#prompt="
        assert_includes result.url, "images=https%3A%2F%2Fexample.com%2Flogo.png"
      end

      test "rejects a blank prompt" do
        assert_raises(ArgumentError) { BuildWithUrlLauncher.new.call(prompt: "") }
      end

      test "safely encodes Japanese line breaks special characters and truncates the official limit" do
        prompt = "日本語のLP\nCTA: 相談&申込? " + ("長" * 60_000)

        result = BuildWithUrlLauncher.new.call(prompt:)
        uri = URI(result.url)
        fragment = URI.decode_www_form(uri.fragment).to_h

        assert_equal 50_000, fragment.fetch("prompt").length
        assert_includes fragment.fetch("prompt"), "日本語のLP\nCTA: 相談&申込?"
        assert_equal "true", URI.decode_www_form(uri.query).to_h.fetch("autosubmit")
      end

      test "uses official Build with URL without MCP credentials and enables MCP only by explicit opt in" do
        assert_equal "lovable_api", Configuration.new(env: {}).connection_mode
        assert_equal(
          "lovable_api",
          Configuration.new(env: { "LOVABLE_MCP_ACCESS_TOKEN" => "token" }).connection_mode
        )
        assert_equal(
          "lovable_mcp",
          Configuration.new(
            env: {
              "LOVABLE_MCP_ACCESS_TOKEN" => "token",
              "LOVABLE_MCP_ENABLED" => "true"
            }
          ).connection_mode
        )
      end
    end
  end
end

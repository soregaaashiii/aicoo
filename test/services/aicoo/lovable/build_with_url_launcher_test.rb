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
    end
  end
end

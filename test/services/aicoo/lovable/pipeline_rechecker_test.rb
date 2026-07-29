require "test_helper"

module Aicoo
  module Lovable
    class PipelineRecheckerTest < ActiveSupport::TestCase
      Configuration = Struct.new(:github_token)
      LandingPage = Struct.new(:landing_page_repository_url, :landing_page_branch)
      Run = Struct.new(:metadata)
      Commit = Struct.new(:commit_sha, :commit_url, :committed_at, :author, :changed_paths)
      Connection = Struct.new(:ok, :code, :project_name, :http_status, :message)
      WebhookConfiguration = Struct.new(:configured?, :diagnostics)

      test "rechecks github without downloading repository artifacts" do
        client = Class.new do
          def initialize(**) end

          def latest_commit!
            PipelineRecheckerTest::Commit.new(
              "abc123",
              "https://github.com/example/lp/commit/abc123",
              "2026-07-29T10:00:00Z",
              "owner",
              %w[index.html app.css]
            )
          end
        end
        result = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new("token"),
          github_client_class: client,
          cloudflare_verifier: Object.new,
          webhook_configuration: WebhookConfiguration.new(true, {})
        ).call(
          component: "github",
          landing_page: LandingPage.new("https://github.com/example/lp", "main"),
          generation_run: Run.new({})
        )

        assert result.ok
        assert_equal "abc123", result.details["commit_sha"]
        assert_equal 2, result.details["changed_file_count"]
      end

      test "diagnoses a missing github token before making a request" do
        client = ->(**) { flunk("GitHub client must not be initialized") }
        result = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new(nil),
          github_client_class: client,
          cloudflare_verifier: Object.new,
          webhook_configuration: WebhookConfiguration.new(true, {})
        ).call(
          component: "github",
          landing_page: LandingPage.new("https://github.com/example/lp", "main"),
          generation_run: Run.new({})
        )

        assert_not result.ok
        assert_equal "github_token_missing", result.code
        assert_includes result.cause, "AICOO_GITHUB_TOKEN"
      end

      test "returns a diagnosis when github connection check times out" do
        client = Class.new do
          def initialize(**) end

          def latest_commit!
            raise Net::ReadTimeout, "execution expired"
          end
        end
        result = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new("token"),
          github_client_class: client,
          cloudflare_verifier: Object.new,
          webhook_configuration: WebhookConfiguration.new(true, {})
        ).call(
          component: "github",
          landing_page: LandingPage.new("https://github.com/example/lp", "main"),
          generation_run: Run.new({})
        )

        assert_not result.ok
        assert_equal "github_connection_failed", result.code
        assert_includes result.cause, "execution expired"
      end

      test "reports cloudflare project and token failures from existing verifier" do
        verifier = Struct.new(:result) do
          def check_connection = result
        end.new(
          Connection.new(false, "api_token_invalid", "aicoo-lp", 403, "Cloudflare API Tokenが無効または期限切れです。")
        )
        result = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new("token"),
          github_client_class: Object,
          cloudflare_verifier: verifier,
          webhook_configuration: WebhookConfiguration.new(true, {})
        ).call(component: "cloudflare", landing_page: nil, generation_run: Run.new({}))

        assert_not result.ok
        assert_equal "api_token_invalid", result.code
        assert_equal 403, result.details["http_status"]
      end

      test "distinguishes webhook secret mismatch and missing receipt" do
        mismatch = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new("token"),
          github_client_class: Object,
          cloudflare_verifier: Object.new,
          webhook_configuration: WebhookConfiguration.new(true, { "last_status" => "signature_mismatch" })
        ).call(component: "webhook", landing_page: nil, generation_run: Run.new({}))
        unreceived = PipelineRechecker.new(
          cloudflare_configuration: Configuration.new("token"),
          github_client_class: Object,
          cloudflare_verifier: Object.new,
          webhook_configuration: WebhookConfiguration.new(true, {})
        ).call(component: "webhook", landing_page: nil, generation_run: Run.new({}))

        assert_equal "signature_mismatch", mismatch.code
        assert_equal "webhook_not_received", unreceived.code
      end
    end
  end
end

require "test_helper"

module Aicoo
  module CloudflarePages
    class DeploymentVerifierTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(name: "Cloudflare検証事業", status: "launched", business_type: "landing_page")
        @landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
          name: "公開LP",
          source_type: "manual",
          ga4_page_path: "/published",
          public_status: "testing"
        )
        @landing_page.update!(metadata: @landing_page.metadata.merge(
          "cloudflare_url" => "https://aicoo-lp.pages.dev/published/",
          "github_commit_sha" => "abcdef123456"
        ))
      end

      test "marks landing page published after matching deployment and url are successful" do
        configuration = Configuration.new(env: {
          "CLOUDFLARE_ACCOUNT_ID" => "account",
          "CLOUDFLARE_API_TOKEN" => "token",
          "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
        })
        adapter = lambda do |uri, _request|
          if uri.host == "api.cloudflare.com"
            response(Net::HTTPOK, {
              success: true,
              result: [
                {
                  id: "deploy-1",
                  latest_stage: { status: "success" },
                  deployment_trigger: { metadata: { commit_hash: "abcdef123456" } }
                }
              ]
            }.to_json)
          else
            response(Net::HTTPOK, "ok")
          end
        end

        result = DeploymentVerifier.new(configuration:, http_adapter: adapter).call(
          landing_page: @landing_page,
          commit_sha: "abcdef123456"
        )

        assert result.completed
        assert_equal "deployed", result.status
        metadata = @landing_page.reload.metadata
        assert_equal "published", metadata["lp_public_status"]
        assert_equal "deployed", metadata["cloudflare_deploy_status"]
        assert_equal "deploy-1", metadata["cloudflare_deployment_id"]
        assert metadata["last_published_at"].present?
      end

      test "keeps deployment pending while cloudflare has not returned the commit" do
        configuration = Configuration.new(env: {
          "CLOUDFLARE_ACCOUNT_ID" => "account",
          "CLOUDFLARE_API_TOKEN" => "token",
          "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
        })
        adapter = ->(_uri, _request) { response(Net::HTTPOK, { success: true, result: [] }.to_json) }

        result = DeploymentVerifier.new(configuration:, http_adapter: adapter).call(
          landing_page: @landing_page,
          commit_sha: "abcdef123456"
        )

        assert_not result.completed
        assert_equal "pending", result.status
        assert_equal "testing", @landing_page.reload.landing_page_public_status
      end

      private

      def response(klass, body)
        klass.new("1.1", klass == Net::HTTPOK ? "200" : "500", "response").tap do |response|
          response.define_singleton_method(:body) { body }
        end
      end
    end
  end
end

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
        @run = AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "succeeded",
          metadata: {
            "pipeline" => "lovable",
            "pipeline_status" => "cloudflare_waiting"
          }
        )
        @landing_page.update!(
          metadata: @landing_page.metadata.merge("lovable_generation_run_id" => @run.id)
        )
      end

      test "marks landing page published and registers the initial service url after real html is verified" do
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
            response(
              Net::HTTPOK,
              "<!doctype html><html><head><title>AI電話受付</title></head><body>voice-analysis-pro</body></html>",
              content_type: "text/html; charset=utf-8"
            )
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
        assert_equal 200, metadata["cloudflare_http_status"]
        assert_equal "AI電話受付", metadata["cloudflare_page_title"]
        assert_equal "HTTP 200・実LP確認完了", metadata["cloudflare_last_message"]
        assert_equal "https://aicoo-lp.pages.dev/published/", metadata["service_url"]
        assert_equal "Service URLを自動登録しました", metadata["service_url_auto_registration_message"]
        assert metadata["last_published_at"].present?

        run_metadata = @run.reload.metadata
        assert_equal "Cloudflare公開URLを取得しました", run_metadata["cloudflare_public_url_acquired_message"]
        assert_equal "Service URLを自動登録しました", run_metadata["service_url_auto_registration_message"]
        overview = Aicoo::Lovable::PipelineOverview.new(
          generation_run: @run,
          landing_page: @landing_page,
          task: nil,
          business: @business
        )
        assert overview.history.any? { |entry| entry.label == "Cloudflare公開URLを取得しました" }
        assert overview.history.any? { |entry| entry.label == "Service URLを自動登録しました" }
      end

      test "does not overwrite an existing service url on update publication" do
        service = @business.business_services.create!(
          name: "既存Service",
          status: "production",
          url: "https://service.example.com"
        )
        result = verifier_with_page(
          "<!doctype html><html><head><title>更新LP</title></head><body>更新済みLP</body></html>"
        ).call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert result.completed
        assert_equal "https://service.example.com", service.reload.url
        assert_nil @landing_page.reload.metadata["service_url"]
        assert_nil @run.reload.metadata["service_url_auto_registration_message"]
      end

      test "completes publication and preserves a GA4 warning when Measurement ID is missing" do
        @run.update!(metadata: @run.metadata.merge(
          "static_validation_warnings" => [
            Aicoo::Lovable::StaticArtifactValidator::GA4_MISSING_WARNING
          ]
        ))

        result = verifier_with_page(
          "<!doctype html><html><head><title>公開LP</title></head><body>voice-analysis-pro</body></html>"
        ).call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert result.completed
        landing_page_metadata = @landing_page.reload.metadata
        assert_equal "published", landing_page_metadata["lp_public_status"]
        assert_equal "deployed", landing_page_metadata["cloudflare_deploy_status"]
        assert_equal "completed", landing_page_metadata["pipeline_stage"]
        assert_equal(
          Aicoo::Lovable::StaticArtifactValidator::GA4_MISSING_WARNING,
          landing_page_metadata["ga4_measurement_warning"]
        )

        run_metadata = @run.reload.metadata
        assert_equal "completed", run_metadata["pipeline_status"]
        assert_equal(
          Aicoo::Lovable::StaticArtifactValidator::GA4_PUBLICATION_NOTICE,
          run_metadata["publication_notice"]
        )
        assert_nil run_metadata["measurement_started_at"]
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

      test "does not save a service url when the Cloudflare deployment fails" do
        configuration = Configuration.new(env: {
          "CLOUDFLARE_ACCOUNT_ID" => "account",
          "CLOUDFLARE_API_TOKEN" => "token",
          "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
        })
        adapter = lambda do |_uri, _request|
          response(Net::HTTPOK, {
            success: true,
            result: [
              {
                id: "deploy-failed",
                latest_stage: { status: "failure" },
                deployment_trigger: { metadata: { commit_hash: "abcdef123456" } }
              }
            ]
          }.to_json)
        end

        result = DeploymentVerifier.new(configuration:, http_adapter: adapter).call(
          landing_page: @landing_page,
          commit_sha: "abcdef123456"
        )

        assert_not result.completed
        assert_equal "failed", result.status
        assert_nil @landing_page.reload.metadata["service_url"]
      end

      test "does not publish or save a service url for the generic Cloudflare page" do
        result = verifier_with_page(
          "<!doctype html><html><head><title>AICOO LP</title></head><body>Cloudflare Pages is ready.</body></html>"
        ).call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert_not result.completed
        assert_equal "pending", result.status
        assert_includes result.message, "汎用初期ページ"
        assert_nil @landing_page.reload.metadata["service_url"]
      end

      test "does not publish or save a service url for HTTP 500" do
        verifier = verifier_with_page(
          "<html><head><title>Error</title></head><body>error</body></html>",
          page_status: Net::HTTPInternalServerError
        )

        result = verifier.call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert_not result.completed
        assert_includes result.message, "HTTP 500"
        assert_nil @landing_page.reload.metadata["service_url"]
      end

      test "does not publish or save a service url when HTML cannot be obtained" do
        result = verifier_with_page(
          '{"status":"ok"}',
          content_type: "application/json"
        ).call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert_not result.completed
        assert_includes result.message, "HTMLを取得できません"
        assert_nil @landing_page.reload.metadata["service_url"]
      end

      test "does not save a service url when the Cloudflare url is unavailable" do
        @landing_page.update!(
          location: "manual://published",
          metadata: @landing_page.metadata.except("cloudflare_url", "lp_url")
        )

        result = verifier_with_page(
          "<!doctype html><html><head><title>LP</title></head><body>LP</body></html>"
        ).call(landing_page: @landing_page, commit_sha: "abcdef123456")

        assert_not result.completed
        assert_includes result.message, "公開確認に失敗"
        assert_nil @landing_page.reload.metadata["service_url"]
      end

      test "diagnoses an invalid cloudflare token without changing a landing page" do
        adapter = lambda do |_uri, _request|
          Struct.new(:body, :code) do
            def is_a?(klass)
              klass == Net::HTTPSuccess ? false : super
            end
          end.new({ success: false, errors: [ { message: "Forbidden" } ] }.to_json, "403")
        end
        verifier = DeploymentVerifier.new(
          configuration: Configuration.new(
            env: {
              "CLOUDFLARE_ACCOUNT_ID" => "account",
              "CLOUDFLARE_API_TOKEN" => "expired",
              "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
            }
          ),
          http_adapter: adapter
        )

        result = verifier.check_connection

        assert_not result.ok
        assert_equal "api_token_invalid", result.code
        assert_equal 403, result.http_status
      end

      test "checks the pages project selected by the landing page business" do
        BusinessDataSourceSetting.create!(
          business: @business,
          source_key: "cloudflare_pages",
          property_identifier: "business-project",
          endpoint_url: "https://business-project.pages.dev",
          connection_status: "linked"
        )
        requested_path = nil
        adapter = lambda do |uri, _request|
          requested_path = uri.path
          response(Net::HTTPOK, { success: true, result: { name: "business-project" } }.to_json)
        end
        verifier = DeploymentVerifier.new(
          configuration: Configuration.new(env: {
            "CLOUDFLARE_ACCOUNT_ID" => "account",
            "CLOUDFLARE_API_TOKEN" => "token",
            "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
          }),
          http_adapter: adapter
        )

        result = verifier.check_connection(business: @business)

        assert result.ok
        assert_equal "business-project", result.project_name
        assert_equal "/client/v4/accounts/account/pages/projects/business-project", requested_path
      end

      private

      def verifier_with_page(body, page_status: Net::HTTPOK, content_type: "text/html; charset=utf-8")
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
            response(page_status, body, content_type:)
          end
        end
        DeploymentVerifier.new(configuration:, http_adapter: adapter)
      end

      def response(klass, body, content_type: "application/json")
        klass.new("1.1", klass == Net::HTTPOK ? "200" : "500", "response").tap do |response|
          response["content-type"] = content_type
          response.define_singleton_method(:body) { body }
        end
      end
    end
  end
end

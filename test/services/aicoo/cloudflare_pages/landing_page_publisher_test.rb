require "test_helper"

module Aicoo
  module CloudflarePages
    class LandingPagePublisherTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      class FakeClient
        attr_reader :commits

        def initialize(paths: [])
          @paths = paths
          @commits = []
        end

        def commit!(files:, deleted_paths: [], message:)
          commits << { files:, deleted_paths:, message: }
          GithubRepositoryClient::Result.new(
            commit_sha: "abc123",
            commit_url: "https://github.com/soregaaashiii/aicoo-lp/commit/abc123",
            changed_paths: files.keys + deleted_paths
          )
        end

        def paths_under(_prefix)
          @paths
        end
      end

      setup do
        @business = Business.create!(
          name: "Cloudflare LP事業",
          description: "LP専用公開テスト",
          status: "launched",
          business_type: "landing_page"
        )
        @campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo")
        @landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "料金",
          source_type: "manual",
          ga4_page_path: "/ai-reception/price",
          public_status: "testing"
        )
        @configuration = Configuration.new(env: {
          "AICOO_GITHUB_TOKEN" => "token",
          "AICOO_LP_GITHUB_REPOSITORY" => "https://github.com/soregaaashiii/aicoo-lp",
          "CLOUDFLARE_PROJECT_NAME" => "aicoo-lp"
        })
      end

      test "publishes one landing page bundle under its public path without touching service repository" do
        service_profile = @business.create_business_execution_profile!(
          repository_name: "service",
          repository_type: "rails",
          github_repository: "https://github.com/example/service",
          active: true
        )
        client = FakeClient.new
        publisher = LandingPagePublisher.new(configuration: @configuration, client:)

        assert_enqueued_with(job: Aicoo::CloudflarePagesDeploymentVerificationJob) do
          result = publisher.publish!(landing_page: @landing_page)

          assert_equal "public/ai-reception/price/", result.github_path
          assert_equal "https://aicoo-lp.pages.dev/ai-reception/price/", result.cloudflare_url
          assert_equal %w[
            public/ai-reception/price/app.js
            public/ai-reception/price/index.html
            public/ai-reception/price/styles.css
          ], client.commits.first.fetch(:files).keys.sort
          assert_equal "Generate LP", client.commits.first.fetch(:message)
        end

        metadata = @landing_page.reload.metadata
        assert_equal "https://github.com/soregaaashiii/aicoo-lp", metadata["lp_publication_repository_url"]
        assert_equal "deploying", metadata["cloudflare_deploy_status"]
        assert_equal "abc123", metadata["github_commit_sha"]
        assert_equal 3, metadata["last_push_file_count"]
        assert_equal 3, metadata["last_push_changed_paths"].size
        assert_operator metadata["last_push_duration_ms"], :>=, 0
        assert_equal "https://github.com/example/service", service_profile.reload.github_repository
      end

      test "publishes with the business selected pages project and domain" do
        BusinessDataSourceSetting.create!(
          business: @business,
          source_key: "cloudflare_pages",
          property_identifier: "selected-project",
          endpoint_url: "https://lp.example.com",
          connection_status: "linked"
        )
        client = FakeClient.new

        result = LandingPagePublisher.new(configuration: @configuration, client:).publish!(landing_page: @landing_page)

        assert_equal "https://lp.example.com/ai-reception/price/", result.cloudflare_url
        assert_equal "selected-project", @landing_page.reload.metadata["cloudflare_project_name"]
      end

      test "uses supplied lovable output files when present" do
        run = AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "succeeded",
          generated_count: 1,
          metadata: {
            "request_type" => "revision",
            "publication_files" => {
              "dist/index.html" => "<h1>Lovable</h1>",
              "dist/assets/app.css" => "body{}"
            }
          }
        )
        client = FakeClient.new

        LandingPagePublisher.new(configuration: @configuration, client:).publish!(
          landing_page: @landing_page,
          generation_run: run
        )

        files = client.commits.first.fetch(:files)
        assert_equal "<h1>Lovable</h1>", files.fetch("public/ai-reception/price/index.html")
        assert_equal "body{}", files.fetch("public/ai-reception/price/assets/app.css")
        assert_equal "Improve LP", client.commits.first.fetch(:message)
        assert_equal "lovable_output", @landing_page.reload.metadata["asset_source"]
      end

      test "decodes structured lovable output files including binary assets" do
        run = AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "succeeded",
          generated_count: 1,
          metadata: {
            "publication_files" => {
              "public/index.html" => { "content" => "<h1>Structured</h1>" },
              "public/images/logo.png" => {
                "content" => Base64.strict_encode64("\x89PNG".b),
                "encoding" => "base64"
              }
            }
          }
        )
        client = FakeClient.new

        LandingPagePublisher.new(configuration: @configuration, client:).publish!(
          landing_page: @landing_page,
          generation_run: run
        )

        files = client.commits.first.fetch(:files)
        assert_equal "<h1>Structured</h1>", files.fetch("public/ai-reception/price/index.html")
        assert_equal "\x89PNG".b, files.fetch("public/ai-reception/price/images/logo.png")
      end

      test "different variant path is published without overwriting source landing page" do
        client = FakeClient.new
        publisher = LandingPagePublisher.new(configuration: @configuration, client:)
        publisher.publish!(landing_page: @landing_page)
        variant = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "料金 B",
          source_type: "manual",
          ga4_page_path: "/ai-reception/price-b1",
          public_status: "testing"
        )

        publisher.publish!(landing_page: variant)

        assert_equal "public/ai-reception/price/", @landing_page.reload.metadata["github_path"]
        assert_equal "public/ai-reception/price-b1/", variant.reload.metadata["github_path"]
        assert_equal 2, client.commits.size
      end

      test "rejects a path already used by another landing page" do
        @landing_page.update!(metadata: @landing_page.metadata.merge("github_path" => "public/shared/"))
        other_business = Business.create!(name: "別LP事業", status: "launched", business_type: "landing_page")
        other = Aicoo::LpIntegration::LandingPageRegistry.new(business: other_business).save!(
          name: "重複LP",
          source_type: "manual",
          ga4_page_path: "/shared"
        )

        error = assert_raises(ArgumentError) do
          LandingPagePublisher.new(configuration: @configuration, client: FakeClient.new).publish!(landing_page: other)
        end

        assert_includes error.message, "使用中"
      end

      test "deletes all files below the stored github path in one commit" do
        @landing_page.update!(metadata: @landing_page.metadata.merge("github_path" => "public/ai-reception/price/"))
        paths = %w[
          public/ai-reception/price/index.html
          public/ai-reception/price/styles.css
        ]
        client = FakeClient.new(paths:)

        result = LandingPagePublisher.new(configuration: @configuration, client:).delete!(landing_page: @landing_page)

        assert result.deleted
        assert_equal paths, client.commits.first.fetch(:deleted_paths)
        assert_equal({}, client.commits.first.fetch(:files))
        assert_equal "Delete LP: 料金", client.commits.first.fetch(:message)
      end

      test "unpublished landing page can be removed without github credentials" do
        configuration = Configuration.new(env: {})

        result = LandingPagePublisher.new(configuration:, client: FakeClient.new).delete!(landing_page: @landing_page)

        assert result.deleted
        assert_nil result.commit_sha
      end
    end
  end
end

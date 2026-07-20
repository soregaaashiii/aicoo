require "test_helper"

module Aicoo
  module Lovable
    class LandingPagePipelineTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      class FakeClient
        attr_reader :calls

        def initialize
          @calls = []
        end

        def configured?
          true
        end

        def create_project(description:, initial_message:)
          calls << [ :create_project, description, initial_message ]
          {
            "project_id" => "lovable-project-1",
            "preview_url" => "https://lovable-project-1.lovable.app",
            "editor_url" => "https://lovable.dev/projects/lovable-project-1"
          }
        end

        def get_project(project_id:)
          calls << [ :get_project, project_id ]
          {
            "project_id" => project_id,
            "preview_url" => "https://#{project_id}.lovable.app",
            "editor_url" => "https://lovable.dev/projects/#{project_id}",
            "latest_commit_sha" => "abc123"
          }
        end

        def send_message(project_id:, message:)
          calls << [ :send_message, project_id, message ]
          { "message_id" => "message-2" }
        end

        def get_diff(project_id:, message_id:)
          calls << [ :get_diff, project_id, message_id ]
          { "diff" => "+ revised CTA" }
        end
      end

      setup do
        @business = businesses(:suelog)
        @client = FakeClient.new
        @configuration = Configuration.new(env: {
          "LOVABLE_MCP_ACCESS_TOKEN" => "test-token",
          "LOVABLE_WORKSPACE_ID" => "test-workspace"
        })
        @pipeline = LandingPagePipeline.new(client: @client, configuration: @configuration)
        clear_enqueued_jobs
      end

      teardown do
        clear_enqueued_jobs
      end

      test "creates and stores a Lovable LP version without a migration" do
        assert_difference([ "AicooLabLandingPage.count", "AicooLabGenerationRun.count" ], 1) do
          result = @pipeline.enqueue_create!(business: @business)
          assert_equal "mcp", result.mode
          assert_equal "draft", result.generation_run.status
          assert_enqueued_with(job: Aicoo::LovableLandingPageGenerationJob, args: [ result.generation_run.id ])
          @pipeline.execute!(result.generation_run)
        end

        run = VersionRepository.new(business: @business).current
        assert_equal "succeeded", run.status
        assert_equal 1, run.metadata["version"]
        assert_equal "preview_ready", run.metadata["pipeline_status"]
        assert_equal "https://lovable-project-1.lovable.app", run.metadata["preview_url"]
        assert_equal "lovable", AicooLabLandingPage.find(run.metadata["landing_page_id"]).generation_source
        assert_includes run.prompt, @business.name
        assert_includes run.prompt, "Lovable側から本番公開は行わない"
      end

      test "revision keeps the same project and creates a new version with diff" do
        first = @pipeline.enqueue_create!(business: @business).generation_run
        @pipeline.execute!(first)

        second = @pipeline.enqueue_revision!(business: @business, change_request: "CTAを目立たせる").generation_run
        @pipeline.execute!(second)

        assert_equal 2, second.reload.metadata["version"]
        assert_equal first.id, second.metadata["previous_run_id"]
        assert_equal "lovable-project-1", second.metadata["project_id"]
        assert_equal "+ revised CTA", second.metadata.dig("diff", "diff")
        assert @client.calls.any? { |call| call.first == :send_message && call.second == "lovable-project-1" }
      end

      test "failed generation preserves the previous successful version" do
        first = @pipeline.enqueue_create!(business: @business).generation_run
        @pipeline.execute!(first)
        broken_client = Object.new
        broken_client.define_singleton_method(:configured?) { true }
        broken_client.define_singleton_method(:send_message) { |**| raise McpClient::Error, "Lovable unavailable" }
        broken_pipeline = LandingPagePipeline.new(client: broken_client, configuration: @configuration)
        second = broken_pipeline.enqueue_revision!(business: @business, change_request: "背景を暗くする").generation_run

        assert_raises(McpClient::Error) { broken_pipeline.execute!(second) }

        assert_equal "failed", second.reload.status
        assert_equal first.id, VersionRepository.new(business: @business).current.id
        assert_equal "Lovable unavailable", second.error_message
      end

      test "falls back to Build URL and supports manual preview registration" do
        configuration = Configuration.new(env: {})
        pipeline = LandingPagePipeline.new(client: McpClient.new(configuration:), configuration:)

        result = pipeline.enqueue_create!(business: @business)

        assert_equal "build_url", result.mode
        assert_equal "lovable_handoff_required", result.generation_run.metadata["pipeline_status"]
        assert_includes result.generation_run.metadata["build_url"], "autosubmit=true"

        pipeline.register_preview!(
          business: @business,
          generation_run: result.generation_run,
          preview_url: "https://manual-preview.lovable.app",
          project_id: "manual-project"
        )
        assert_equal "preview_ready", result.generation_run.reload.metadata["pipeline_status"]
        assert_equal "manual-project", result.generation_run.metadata["project_id"]
      end

      test "restores a successful version as a new current version" do
        first = @pipeline.enqueue_create!(business: @business).generation_run
        @pipeline.execute!(first)
        second = @pipeline.enqueue_revision!(business: @business, change_request: "CTAを目立たせる").generation_run
        @pipeline.execute!(second)

        restored = @pipeline.restore!(business: @business, generation_run: first).generation_run

        assert_equal 3, restored.metadata["version"]
        assert_equal first.id, restored.metadata["restored_from_run_id"]
        assert_equal first.metadata["preview_url"], restored.metadata["preview_url"]
        assert_equal restored.id, VersionRepository.new(business: @business).current.id
      end
    end
  end
end

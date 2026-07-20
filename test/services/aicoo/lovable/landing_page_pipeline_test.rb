require "test_helper"

module Aicoo
  module Lovable
    class LandingPagePipelineTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @business = businesses(:suelog)
        @configuration = Configuration.new(env: { "LOVABLE_MCP_ACCESS_TOKEN" => "unused-token" })
        @pipeline = LandingPagePipeline.new(configuration: @configuration)
        clear_enqueued_jobs
      end

      teardown do
        clear_enqueued_jobs
      end

      test "prepares and stores an editable prompt version without launching Lovable" do
        assert_difference([ "AicooLabLandingPage.count", "AicooLabGenerationRun.count" ], 1) do
          result = @pipeline.prepare_create!(business: @business)

          assert_equal "prompt_review", result.mode
          assert_equal "draft", result.generation_run.status
          assert_equal "prompt_ready", result.generation_run.metadata["pipeline_status"]
          assert_equal "v1.p1", result.generation_run.metadata["prompt_version"]
          assert_nil result.generation_run.metadata["build_url"]
          assert_no_enqueued_jobs only: Aicoo::LovableLandingPageGenerationJob
        end
      end

      test "launches every prompt through official Build with URL even when MCP token exists" do
        run = @pipeline.prepare_create!(business: @business).generation_run
        result = @pipeline.launch!(business: @business, generation_run: run)

        assert_equal "build_url", result.mode
        assert_equal "succeeded", run.reload.status
        assert_equal "lovable_handoff_required", run.metadata["pipeline_status"]
        assert_equal "build_with_url", run.metadata["launcher"]
        assert_equal "official_build_with_url", run.metadata["handoff_reason"]
        assert_includes run.metadata["build_url"], "https://lovable.dev/?autosubmit=true#prompt="
        assert_no_enqueued_jobs only: Aicoo::LovableLandingPageGenerationJob
      end

      test "updates and regenerates the saved prompt version" do
        run = @pipeline.prepare_create!(business: @business).generation_run

        @pipeline.update_prompt!(business: @business, generation_run: run, prompt: "Owner edited prompt")
        assert_equal "Owner edited prompt", run.reload.prompt
        assert_equal "v1.p2", run.metadata["prompt_version"]

        @pipeline.regenerate_prompt!(business: @business, generation_run: run)
        assert_includes run.reload.prompt, @business.name
        assert_equal "v1.p3", run.metadata["prompt_version"]
      end

      test "revision keeps the previous version and records the requested difference" do
        first = @pipeline.enqueue_create!(business: @business).generation_run
        @pipeline.register_preview!(
          business: @business,
          generation_run: first,
          preview_url: "https://first-preview.lovable.app",
          project_id: "lovable-project-1"
        )

        second = @pipeline.prepare_revision!(business: @business, change_request: "CTAを目立たせる").generation_run
        @pipeline.launch!(business: @business, generation_run: second)

        assert_equal 2, second.reload.metadata["version"]
        assert_equal first.id, second.metadata["previous_run_id"]
        assert_equal "CTAを目立たせる", second.metadata["change_request"]
        assert_includes second.prompt, "CTAを目立たせる"
        assert_includes second.prompt, "修正対象以外"
      end

      test "LP learning candidate is preserved in a Lovable revision prompt" do
        first = @pipeline.enqueue_create!(business: @business).generation_run
        @pipeline.register_preview!(business: @business, generation_run: first, preview_url: "https://first-preview.lovable.app")
        candidate = @business.action_candidates.create!(
          title: "吸えログ LPのCTAを改善する",
          action_type: "ui_improvement",
          status: "proposal",
          generation_source: "lp_learning",
          department: "revenue",
          immediate_value_yen: 0,
          success_probability: 0.6,
          metadata: {
            "execution_mode" => "lovable_revision",
            "lovable_change_request" => "CTAだけを改善し、その他は維持してください。"
          }
        )

        second = @pipeline.prepare_revision!(
          business: @business,
          action_candidate: candidate,
          change_request: candidate.metadata["lovable_change_request"]
        ).generation_run

        assert_equal candidate.id, second.metadata["action_candidate_id"]
        assert_includes second.prompt, "CTAだけを改善"
        assert_includes second.prompt, "修正対象以外"
      end

      test "supports manual preview registration after Build with URL handoff" do
        result = @pipeline.enqueue_create!(business: @business)

        @pipeline.register_preview!(
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
        @pipeline.register_preview!(business: @business, generation_run: first, preview_url: "https://first-preview.lovable.app")
        second = @pipeline.enqueue_revision!(business: @business, change_request: "CTAを目立たせる").generation_run
        @pipeline.register_preview!(business: @business, generation_run: second, preview_url: "https://second-preview.lovable.app")

        restored = @pipeline.restore!(business: @business, generation_run: first).generation_run

        assert_equal 3, restored.metadata["version"]
        assert_equal first.id, restored.metadata["restored_from_run_id"]
        assert_equal first.metadata["preview_url"], restored.metadata["preview_url"]
        assert_equal restored.id, VersionRepository.new(business: @business).current.id
      end
    end
  end
end

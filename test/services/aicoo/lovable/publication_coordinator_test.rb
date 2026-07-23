require "test_helper"
require "ostruct"

module Aicoo
  module Lovable
    class PublicationCoordinatorTest < ActiveSupport::TestCase
      class FakeGithubBridge
        def initialize(submission)
          @submission = submission
        end

        def call
          @submission.mark_submitted!(payload: {
            "github_issue_url" => "https://github.com/example/suelog/issues/99",
            "github_issue_number" => 99
          })
          OpenStruct.new(
            issue_url: "https://github.com/example/suelog/issues/99",
            issue_number: 99,
            message: "created"
          )
        end
      end

      setup do
        @business = businesses(:suelog)
        BusinessExecutionProfile.create!(
          business: @business,
          repository_name: "suelog",
          repository_type: "rails",
          repository_path: "/apps/suelog",
          github_repository: "https://github.com/example/suelog",
          test_command: "bin/rails test",
          lint_command: "bin/rails zeitwerk:check",
          deploy_command: "bin/deploy",
          codex_enabled: true,
          codex_workspace_name: "AICOO",
          codex_project_folder: "/workspace/suelog",
          codex_repository_url: "https://github.com/example/suelog",
          codex_base_branch: "main",
          codex_working_branch_prefix: "aicoo/",
          codex_risk_limit: "low",
          target_paths: [ "app/views/lp" ],
          require_manual_approval: true
        )
        configuration = Configuration.new(env: {})
        pipeline = LandingPagePipeline.new(client: McpClient.new(configuration:), configuration:)
        @run = pipeline.enqueue_create!(business: @business).generation_run
        pipeline.register_preview!(
          business: @business,
          generation_run: @run,
          preview_url: "https://preview.lovable.app",
          project_id: "project-1"
        )
      end

      test "publishes only through the existing Codex and Git path" do
        result = PublicationCoordinator.new(github_bridge_class: FakeGithubBridge).call(
          business: @business,
          generation_run: @run
        )

        assert_equal "build_lp", result.action_candidate.action_type
        assert_equal "lovable", result.action_candidate.metadata["source_system"]
        assert_equal true, result.action_candidate.metadata["lovable_deploy_forbidden"]
        assert_equal "ready", Aicoo::ActionCandidateExecutionReadiness.call(result.action_candidate).readiness
        assert_equal @run.id, result.auto_revision_task.metadata["lovable_generation_run_id"]
        assert_equal "submitted", result.codex_submission.status
        assert_equal "codex_submitted", @run.reload.metadata.dig("publication", "status")
        assert_equal false, @run.metadata.dig("publication", "published")
      end

      test "does not publish a version without preview" do
        @run.update!(metadata: @run.metadata.to_h.except("preview_url"))

        assert_raises(ArgumentError) do
          PublicationCoordinator.new(github_bridge_class: FakeGithubBridge).call(business: @business, generation_run: @run)
        end
        assert_empty @business.codex_submissions
      end

      test "records publication metadata only after the Codex deploy completes" do
        result = PublicationCoordinator.new(github_bridge_class: FakeGithubBridge).call(
          business: @business,
          generation_run: @run
        )

        result.codex_submission.update_tracking!(
          pull_request_url: "https://github.com/example/suelog/pull/12",
          commit_sha: "abc123",
          merge_status: "merged",
          deploy_status: "deployed",
          deploy_url: "https://suelog.example.com"
        )

        publication = @run.reload.metadata.dig("publication")
        assert_equal true, publication["published"]
        assert_equal "abc123", publication["commit_sha"]
        assert_equal "https://suelog.example.com", publication["production_url"]
        assert publication["published_at"].present?
        assert_equal "collecting", @run.metadata.dig("learning", "measurement_status")
      end

      test "external landing page publication targets its repository and cloudflare" do
        campaign = @business.business_campaigns.create!(name: "LP SEO", campaign_type: "seo", status: "active")
        prototype = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
          campaign_id: campaign.id,
          name: "SEO LP",
          source_type: "github",
          repository_url: "https://github.com/example/seo-lp",
          branch: "main",
          public_status: "testing",
          ga4_page_path: "/seo-lp"
        )
        @run.update!(metadata: @run.metadata.to_h.merge(
          "landing_page_prototype_id" => prototype.id,
          "campaign_id" => campaign.id
        ))

        result = PublicationCoordinator.new(github_bridge_class: FakeGithubBridge).call(
          business: @business,
          generation_run: @run
        )

        assert_equal "https://github.com/example/seo-lp", result.auto_revision_task.effective_codex_repository_url
        assert_equal "cloudflare_pages", result.auto_revision_task.effective_deploy_target
        assert_equal true, result.auto_revision_task.metadata.to_h["service_repository_protected"]
        assert_equal false, result.auto_revision_task.metadata.to_h["auto_deploy_enabled"]
        assert_includes result.action_candidate.execution_prompt, "Service本体のRepositoryは変更しません"
        assert_not_includes result.action_candidate.execution_prompt, "https://github.com/example/suelog\nBase Branch"
      end
    end
  end
end

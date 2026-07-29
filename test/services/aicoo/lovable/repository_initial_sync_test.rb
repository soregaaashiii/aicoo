require "test_helper"

module Aicoo
  module Lovable
    class RepositoryInitialSyncTest < ActiveSupport::TestCase
      class RecordingJob
        class << self
          attr_accessor :arguments

          def perform_later(*arguments)
            self.arguments = arguments
          end
        end
      end

      setup do
        @business = Business.create!(
          name: "Repository Sync Business",
          description: "GitHubから既存LPを取り込む",
          status: "building",
          business_type: "saas"
        )
        @campaign = @business.business_campaigns.create!(
          name: "SEO",
          campaign_type: "seo",
          status: "active"
        )
        @landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "Repository LP",
          source_type: "github",
          repository_url: "https://github.com/example/repository-lp",
          branch: "main",
          ga4_page_path: "/repository-lp",
          public_status: "testing"
        )
        RecordingJob.arguments = nil
      end

      test "repository registration creates one version and enqueues latest commit import" do
        result = nil
        assert_difference("AicooLabGenerationRun.count", 1) do
          result = RepositoryInitialSync.new(job_class: RecordingJob).call(
            business: @business,
            landing_page: @landing_page
          )
        end

        run = result.generation_run
        assert result.created
        assert result.enqueued
        assert_equal [ run.id ], RecordingJob.arguments
        assert_equal "v1", run.metadata["version_label"]
        assert_equal "repository_import", run.metadata["request_type"]
        assert_equal true, run.metadata["repository_import"]
        assert_equal "artifact_fetching", run.metadata["pipeline_status"]
        assert_equal run.id, @landing_page.reload.metadata["lovable_generation_run_id"]
        assert @landing_page.metadata["lovable_landing_page_id"].present?
      end

      test "saving the same repository again does not create or enqueue another version" do
        first = RepositoryInitialSync.new(job_class: RecordingJob).call(
          business: @business,
          landing_page: @landing_page
        )
        RecordingJob.arguments = nil

        assert_no_difference("AicooLabGenerationRun.count") do
          second = RepositoryInitialSync.new(job_class: RecordingJob).call(
            business: @business,
            landing_page: @landing_page.reload
          )
          assert_equal first.generation_run.id, second.generation_run.id
          assert_not second.created
          assert_not second.enqueued
        end
        assert_nil RecordingJob.arguments
      end

      test "changing repository after a synced commit creates the next version" do
        first = RepositoryInitialSync.new(job_class: RecordingJob).call(
          business: @business,
          landing_page: @landing_page
        ).generation_run
        first.update!(metadata: first.metadata.to_h.merge(
          "lovable_last_synced_commit_sha" => "old-sha",
          "publication" => { "commit_sha" => "published-sha" }
        ))
        Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).update_owner_settings!(
          landing_page_id: @landing_page.id,
          name: @landing_page.landing_page_name,
          repository_url: "https://github.com/example/replacement-lp",
          branch: "main"
        )
        RecordingJob.arguments = nil

        result = nil
        assert_difference("AicooLabGenerationRun.count", 1) do
          result = RepositoryInitialSync.new(job_class: RecordingJob).call(
            business: @business,
            landing_page: @landing_page.reload
          )
        end

        assert_equal "https://github.com/example/repository-lp", first.reload.metadata["lovable_result_repository"]
        assert_equal "v2", result.generation_run.metadata["version_label"]
        assert_equal "https://github.com/example/replacement-lp", result.generation_run.metadata["lovable_result_repository"]
        assert_equal [ result.generation_run.id ], RecordingJob.arguments
      end
    end
  end
end

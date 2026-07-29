require "test_helper"

module Aicoo
  class LovableResultImportJobTest < ActiveJob::TestCase
    test "passes webhook commit to the importer and records completion" do
      run = AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "github_webhook_received",
          "github_webhook_processing_key" => "example/result:main:source-sha"
        }
      )
      calls = []
      importer = Object.new
      importer.define_singleton_method(:call) do |generation_run:, source_commit_sha:|
        calls << [ generation_run.id, source_commit_sha ]
      end

      Aicoo::Lovable::ResultRepositoryImporter.stub(:new, importer) do
        LovableResultImportJob.perform_now(run.id, "source-sha", "example/result:main:source-sha")
      end

      assert_equal [ [ run.id, "source-sha" ] ], calls
      assert_equal "completed", run.reload.metadata["github_webhook_status"]
      assert_equal "example/result:main:source-sha", run.metadata["github_webhook_processed_key"]
      assert_nil run.metadata["github_webhook_processing_key"]
    end

    test "retries a temporary artifact failure without surfacing owner action" do
      run = AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "github_webhook_received",
          "github_webhook_processing_key" => "example/result:main:source-sha"
        }
      )
      importer = Object.new
      importer.define_singleton_method(:call) do |generation_run:, **|
        generation_run.update!(
          error_message: "temporary timeout",
          metadata: generation_run.metadata.to_h.merge(
            "pipeline_status" => "github_webhook_waiting",
            "lovable_error_code" => "artifact_fetch_failed",
            "lovable_error_message" => "temporary timeout"
          )
        )
        raise Net::ReadTimeout, "temporary timeout"
      end

      assert_enqueued_with(
        job: Aicoo::LovableResultImportJob,
        args: [ run.id, "source-sha", "example/result:main:source-sha" ]
      ) do
        Aicoo::Lovable::ResultRepositoryImporter.stub(:new, importer) do
          LovableResultImportJob.perform_now(run.id, "source-sha", "example/result:main:source-sha")
        end
      end

      metadata = run.reload.metadata
      assert_equal "retrying", metadata["pipeline_recovery_status"]
      assert_equal "retrying", metadata["github_webhook_status"]
      assert_equal 1, metadata["pipeline_retry_count"]
      assert_equal 3, metadata["pipeline_retry_limit"]
      assert metadata["pipeline_next_retry_at"].present?
    end
  end
end

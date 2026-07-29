module Aicoo
  module Lovable
    class RepositoryInitialSync
      Result = Data.define(:generation_run, :created, :enqueued)

      def initialize(
        pipeline: LandingPagePipeline.new,
        job_class: Aicoo::LovableResultImportJob
      )
        @pipeline = pipeline
        @job_class = job_class
      end

      def call(business:, landing_page:)
        return Result.new(generation_run: nil, created: false, enqueued: false) if landing_page.landing_page_repository_url.blank?

        prepared = pipeline.prepare_repository_import!(
          business:,
          landing_page_prototype: landing_page
        )
        created = prepared.mode == "created"
        job_class.perform_later(prepared.generation_run.id) if created
        Result.new(
          generation_run: prepared.generation_run,
          created:,
          enqueued: created
        )
      rescue StandardError => e
        mark_enqueue_failure(prepared&.generation_run, e)
        Result.new(
          generation_run: prepared&.generation_run,
          created: prepared&.mode == "created",
          enqueued: false
        )
      end

      private

      attr_reader :pipeline, :job_class

      def mark_enqueue_failure(run, error)
        return unless run

        run.update!(
          error_message: error.message,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "artifact_fetching",
            "lovable_error_code" => "artifact_fetch_failed",
            "lovable_error_message" => error.message,
            "repository_sync_enqueue_failed_at" => Time.current.iso8601
          )
        )
      end
    end
  end
end

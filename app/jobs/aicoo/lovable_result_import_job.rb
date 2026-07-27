module Aicoo
  class LovableResultImportJob < ApplicationJob
    queue_as :default

    def perform(generation_run_id, source_commit_sha = nil, webhook_key = nil)
      run = AicooLabGenerationRun.find_by(id: generation_run_id)
      return unless run

      Aicoo::Lovable::ResultRepositoryImporter.new.call(
        generation_run: run,
        source_commit_sha:
      )
      complete_webhook!(run, webhook_key, source_commit_sha)
    rescue StandardError => e
      fail_webhook!(run, webhook_key, e) if run
      Rails.logger.error("[LovableResultImportJob] run_id=#{generation_run_id} #{e.class}: #{e.message}")
    end

    private

    def complete_webhook!(run, webhook_key, source_commit_sha)
      return if webhook_key.blank?

      run.reload.update!(metadata: run.metadata.to_h.merge(
        "github_webhook_status" => "completed",
        "github_webhook_processing_key" => nil,
        "github_webhook_processed_key" => webhook_key,
        "github_webhook_commit_sha" => source_commit_sha,
        "github_webhook_completed_at" => Time.current.iso8601
      ))
    end

    def fail_webhook!(run, webhook_key, error)
      run.reload.update!(
        error_message: error.message,
        metadata: run.metadata.to_h.merge(
          "github_webhook_status" => "failed",
          "github_webhook_processing_key" => nil,
          "github_webhook_processed_key" => webhook_key,
          "github_webhook_failed_at" => Time.current.iso8601,
          "lovable_error_message" => error.message
        ).compact
      )
    rescue StandardError => metadata_error
      Rails.logger.error("[LovableResultImportJob] failed to persist webhook failure run_id=#{run.id} #{metadata_error.class}: #{metadata_error.message}")
    end
  end
end

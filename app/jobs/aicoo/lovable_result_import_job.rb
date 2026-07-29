module Aicoo
  class LovableResultImportJob < ApplicationJob
    queue_as :default
    MAX_AUTO_ATTEMPTS = 3
    AUTO_RETRY_WAIT = 30.seconds

    def perform(generation_run_id, source_commit_sha = nil, webhook_key = nil)
      run = AicooLabGenerationRun.find_by(id: generation_run_id)
      return unless run

      Aicoo::Lovable::ResultRepositoryImporter.new.call(
        generation_run: run,
        source_commit_sha:
      )
      complete_webhook!(run, webhook_key, source_commit_sha)
    rescue StandardError => e
      Rails.logger.error("[LovableResultImportJob] run_id=#{generation_run_id} #{e.class}: #{e.message}")
      if run && auto_retryable?(run) && executions.to_i < MAX_AUTO_ATTEMPTS
        schedule_retry!(run, e)
      else
        fail_webhook!(run, webhook_key, e) if run
      end
    end

    private

    def complete_webhook!(run, webhook_key, source_commit_sha)
      return if webhook_key.blank?

      run.reload.update!(
        error_message: nil,
        metadata: run.metadata.to_h.merge(
          "github_webhook_status" => "completed",
          "github_webhook_processing_key" => nil,
          "github_webhook_processed_key" => webhook_key,
          "github_webhook_commit_sha" => source_commit_sha,
          "github_webhook_completed_at" => Time.current.iso8601,
          "pipeline_recovery_status" => nil,
          "pipeline_next_retry_at" => nil,
          "lovable_error_code" => nil,
          "lovable_error_message" => nil
        )
      )
    end

    def auto_retryable?(run)
      run.reload.metadata.to_h["lovable_error_code"].to_s.in?(
        Aicoo::Lovable::PipelineOverview::AUTO_RECOVERABLE_ERROR_CODES
      )
    end

    def schedule_retry!(run, error)
      now = Time.current
      next_retry_at = now + AUTO_RETRY_WAIT
      run.update!(
        error_message: error.message,
        metadata: run.metadata.to_h.merge(
          "github_webhook_status" => "retrying",
          "pipeline_recovery_status" => "retrying",
          "pipeline_retry_count" => executions.to_i,
          "pipeline_retry_limit" => MAX_AUTO_ATTEMPTS,
          "pipeline_last_retry_at" => now.iso8601,
          "pipeline_next_retry_at" => next_retry_at.iso8601
        )
      )
      retry_job wait: AUTO_RETRY_WAIT, error:
    end

    def fail_webhook!(run, webhook_key, error)
      run.reload.update!(
        error_message: error.message,
        metadata: run.metadata.to_h.merge(
          "github_webhook_status" => "failed",
          "github_webhook_processing_key" => nil,
          "github_webhook_processed_key" => webhook_key,
          "github_webhook_failed_at" => Time.current.iso8601,
          "lovable_error_message" => error.message,
          "pipeline_recovery_status" => auto_retryable?(run) ? "exhausted" : nil,
          "pipeline_retry_count" => executions.to_i,
          "pipeline_retry_limit" => MAX_AUTO_ATTEMPTS,
          "pipeline_next_retry_at" => nil
        ).compact
      )
    rescue StandardError => metadata_error
      Rails.logger.error("[LovableResultImportJob] failed to persist webhook failure run_id=#{run.id} #{metadata_error.class}: #{metadata_error.message}")
    end
  end
end

module Aicoo
  class CloudflarePagesDeploymentVerificationJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 10

    def perform(landing_page_id, commit_sha, deleted = false, attempt = 1)
      landing_page = BusinessPrototype.find_by(id: landing_page_id)
      return unless landing_page

      result = Aicoo::CloudflarePages::DeploymentVerifier.new.call(
        landing_page:,
        commit_sha:,
        deleted:
      )
      return if result.completed

      if result.status == "failed" || attempt.to_i >= MAX_ATTEMPTS
        deploy_status = result.status == "failed" ? "failed" : "verification_timeout"
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "cloudflare_deploy_status" => deploy_status,
          "cloudflare_deploy_error" => result.message,
          "cloudflare_last_checked_at" => Time.current.iso8601
        ))
        stamp_generation_run_failure!(landing_page, deploy_status, result.message)
        return
      end

      self.class.set(wait: 30.seconds).perform_later(landing_page_id, commit_sha, deleted, attempt.to_i + 1)
    end

    private

    def stamp_generation_run_failure!(landing_page, deploy_status, message)
      run = AicooLabGenerationRun.find_by(id: landing_page.metadata.to_h["lovable_generation_run_id"])
      return unless run

      error_code = if deploy_status == "failed"
        "cloudflare_failed"
      elsif message.to_s.include?("公開URL")
        "public_url_verification_timeout"
      else
        "cloudflare_verification_timeout"
      end
      run.update!(
        error_message: message,
        metadata: run.metadata.to_h.merge(
          "pipeline_status" => error_code,
          "lovable_error_code" => error_code,
          "lovable_error_message" => message,
          "lovable_last_error_at" => Time.current.iso8601
        )
      )
    end
  end
end

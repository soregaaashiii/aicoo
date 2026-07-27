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
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "cloudflare_deploy_status" => result.status == "failed" ? "failed" : "verification_timeout",
          "cloudflare_deploy_error" => result.message,
          "cloudflare_last_checked_at" => Time.current.iso8601
        ))
        return
      end

      self.class.set(wait: 30.seconds).perform_later(landing_page_id, commit_sha, deleted, attempt.to_i + 1)
    end
  end
end

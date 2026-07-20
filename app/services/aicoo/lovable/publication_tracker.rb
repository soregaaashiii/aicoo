module Aicoo
  module Lovable
    class PublicationTracker
      def self.sync_for_submission(submission)
        run_id = submission.auto_revision_task.metadata.to_h["lovable_generation_run_id"]
        return unless run_id.present?

        run = AicooLabGenerationRun.find_by(id: run_id)
        return unless run

        new(run).sync!(submission:)
      end

      def initialize(generation_run)
        @generation_run = generation_run
      end

      def sync!(submission: nil)
        publication = generation_run.metadata.to_h.fetch("publication", {})
        submission ||= CodexSubmission.find_by(id: publication["codex_submission_id"])
        return publication unless submission

        payload = submission.response_payload.to_h
        deployed = submission.deploy_status.to_s == "deployed" || submission.status == "completed" && payload["deploy_url"].present?
        updated = publication.merge(
          "status" => deployed ? "published" : submission.workflow_status,
          "published" => deployed,
          "production_url" => payload["deploy_url"].presence || submission.auto_revision_task.execution_profile&.production_url,
          "commit_sha" => payload["commit_sha"].presence || payload["head_sha"],
          "deploy_id" => payload["deploy_id"].presence || payload["render_deploy_id"],
          "pull_request_url" => submission.pr_url,
          "merge_status" => submission.merge_status,
          "deploy_status" => submission.deploy_status,
          "published_at" => (publication["published_at"].presence || Time.current.iso8601 if deployed),
          "last_synced_at" => Time.current.iso8601
        ).compact
        generation_run.update!(metadata: generation_run.metadata.to_h.merge("publication" => updated))
        if deployed
          sync_experiment!(updated)
          LearningSummary.new(business: submission.business, generation_run:).call(persist: true)
        end
        updated
      end

      private

      attr_reader :generation_run

      def sync_experiment!(publication)
        landing_page = AicooLabLandingPage.find_by(id: generation_run.metadata.to_h["landing_page_id"])
        return unless landing_page

        landing_page.aicoo_lab_experiment.update!(
          status: "running",
          approval_status: "approved",
          public_url: publication["production_url"],
          published_at: Time.zone.parse(publication["published_at"].to_s)
        )
      end
    end
  end
end

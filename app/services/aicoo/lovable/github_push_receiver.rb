module Aicoo
  module Lovable
    class GithubPushReceiver
      Result = Data.define(:status, :generation_run_id, :landing_page_id, :duplicate, :reason)
      ACTIVE_PIPELINE_STATUSES = %w[
        lovable_handoff_ready
        lovable_generation_waiting
        lovable_result_waiting
        github_webhook_waiting
        waiting_manual_fix
        github_commit_waiting
      ].freeze
      MAX_RECEIPTS = 20

      def initialize(configuration: GithubWebhookConfiguration.new, job_class: Aicoo::LovableResultImportJob)
        @configuration = configuration
        @job_class = job_class
      end

      def call(event:, delivery_id:, payload:)
        job_enqueued = false
        values = payload.to_h.deep_stringify_keys
        return record_non_push(event, delivery_id) unless event.to_s == "push"

        repository = repository_identity(values)
        branch = branch_name(values["ref"])
        commit_sha = values["after"].to_s
        attributes = diagnostic_attributes(delivery_id:, repository:, branch:, commit_sha:)
        return ignored("branch_deleted", attributes) if values["deleted"] == true || commit_sha.match?(/\A0+\z/)
        return failed("repository_missing", attributes) if repository.blank?
        return failed("branch_missing", attributes) if branch.blank?
        return failed("commit_sha_missing", attributes) if commit_sha.blank?
        if repository == GithubRepositoryIdentity.normalize(Aicoo::CloudflarePages::Configuration.new.repository_url)
          return ignored("publication_repository_push", attributes)
        end

        key = [ repository, branch, commit_sha ].join(":")
        duplicate_run, duplicate_landing_page = duplicate_target(repository, branch, key)
        if duplicate_run
          configuration.record!(status: "duplicate", attributes:)
          return Result.new(
            status: "duplicate",
            generation_run_id: duplicate_run.id,
            landing_page_id: duplicate_landing_page&.id,
            duplicate: true,
            reason: "duplicate_push"
          )
        end

        generation_run, landing_page, reason = target_for(repository, branch)
        return failed(reason, attributes) unless generation_run && landing_page

        duplicate = reserve!(generation_run, landing_page, key, attributes)
        if duplicate
          configuration.record!(status: "duplicate", attributes:)
          return Result.new(status: "duplicate", generation_run_id: generation_run.id, landing_page_id: landing_page.id, duplicate: true, reason: "duplicate_push")
        end

        job_class.perform_later(generation_run.id, commit_sha, key)
        job_enqueued = true
        configuration.record!(status: "accepted", attributes: attributes.merge("generation_run_id" => generation_run.id, "landing_page_id" => landing_page.id))
        Result.new(status: "accepted", generation_run_id: generation_run.id, landing_page_id: landing_page.id, duplicate: false, reason: nil)
      rescue StandardError => e
        mark_enqueue_failure(generation_run, key, e) if defined?(generation_run) && generation_run && !job_enqueued
        configuration.record!(
          status: "failed",
          failure: true,
          attributes: (defined?(attributes) ? attributes : {}).merge("error" => "#{e.class}: #{e.message}")
        )
        raise
      end

      private

      attr_reader :configuration, :job_class

      def record_non_push(event, delivery_id)
        status = event.to_s == "ping" ? "ping" : "ignored"
        reason = event.to_s == "ping" ? nil : "unsupported_event"
        configuration.record!(status:, attributes: { "event" => event.to_s, "delivery_id" => delivery_id })
        Result.new(status:, generation_run_id: nil, landing_page_id: nil, duplicate: false, reason:)
      end

      def repository_identity(payload)
        GithubRepositoryIdentity.normalize(
          payload.dig("repository", "full_name").presence ||
            payload.dig("repository", "html_url").presence ||
            payload.dig("repository", "clone_url")
        )
      end

      def branch_name(ref)
        value = ref.to_s
        return unless value.start_with?("refs/heads/")

        value.delete_prefix("refs/heads/")
      end

      def target_for(repository, branch)
        repository_runs = candidate_runs.select do |run|
          GithubRepositoryIdentity.normalize(repository_for(run)) == repository
        end
        return [ nil, nil, "repository_mismatch" ] if repository_runs.empty?

        branch_runs = repository_runs.select do |run|
          branch_for(run) == branch
        end
        return [ nil, nil, "branch_mismatch" ] if branch_runs.empty?

        active_runs = branch_runs.select { |run| active_run?(run) }
        return [ nil, nil, "active_landing_page_not_found" ] if active_runs.empty?

        valid_runs = active_runs.select do |run|
          prototype = prototype_for(run)
          prototype && prototype.business_id == run.metadata.to_h["business_id"].to_i
        end
        return [ nil, nil, "target_landing_page_not_found" ] if valid_runs.empty?

        current_runs = valid_runs.select do |run|
          prototype_for(run).metadata.to_h["lovable_generation_run_id"].to_i == run.id
        end
        eligible_runs = current_runs.presence || valid_runs
        target_ids = eligible_runs.map { |run| run.metadata.to_h["landing_page_prototype_id"].to_i }.uniq
        return [ nil, nil, "target_landing_page_ambiguous" ] if target_ids.size > 1

        run = eligible_runs.max_by(&:created_at)
        [ run, prototype_for(run), nil ]
      end

      def candidate_runs
        @candidate_runs ||= AicooLabGenerationRun
          .where(generation_type: "lp_generation")
          .where("metadata ->> 'pipeline' = ?", "lovable")
          .where("metadata ->> 'landing_page_prototype_id' IS NOT NULL")
          .order(created_at: :desc)
          .to_a
      end

      def duplicate_target(repository, branch, key)
        run = candidate_runs.find do |candidate|
          metadata = candidate.metadata.to_h
          GithubRepositoryIdentity.normalize(repository_for(candidate)) == repository &&
            branch_for(candidate) == branch &&
            Array(metadata["github_webhook_receipts"]).any? { |receipt| receipt.to_h["key"] == key }
        end
        return [ nil, nil ] unless run

        [ run, prototype_for(run) ]
      end

      def candidate_prototypes
        @candidate_prototypes ||= begin
          ids = candidate_runs.filter_map { |run| run.metadata.to_h["landing_page_prototype_id"].presence&.to_i }
          BusinessPrototype.active.external_landing_pages.where(id: ids).index_by(&:id)
        end
      end

      def prototype_for(run)
        candidate_prototypes[run.metadata.to_h["landing_page_prototype_id"].to_i]
      end

      def repository_for(run)
        run.metadata.to_h["lovable_result_repository"].presence ||
          prototype_for(run)&.landing_page_repository_url
      end

      def branch_for(run)
        run.metadata.to_h["lovable_result_branch"].presence ||
          prototype_for(run)&.landing_page_branch.presence ||
          "main"
      end

      def active_run?(run)
        metadata = run.metadata.to_h
        run.status != "failed" &&
          metadata.dig("publication", "published") != true &&
          metadata["pipeline_status"].in?(ACTIVE_PIPELINE_STATUSES)
      end

      def reserve!(run, landing_page, key, attributes)
        duplicate = false
        run.with_lock do
          metadata = run.reload.metadata.to_h
          receipts = Array(metadata["github_webhook_receipts"])
          duplicate = receipts.any? { |receipt| receipt.to_h["key"] == key }
          next if duplicate

          now = Time.current.iso8601
          receipt = attributes.merge("key" => key, "received_at" => now)
          run.update!(
            error_message: nil,
            metadata: metadata.merge(
              "pipeline_status" => "github_webhook_received",
              "lovable_status" => "webhook_received",
              "lovable_result_repository" => repository_for(run),
              "lovable_result_branch" => branch_for(run),
              "github_webhook_status" => "received",
              "github_webhook_processing_key" => key,
              "github_webhook_commit_sha" => attributes["commit_sha"],
              "github_webhook_received_at" => now,
              "github_webhook_receipts" => (receipts + [ receipt ]).last(MAX_RECEIPTS),
              "lovable_error_code" => nil,
              "lovable_error_message" => nil
            )
          )
        end
        return true if duplicate

        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "planning_status" => "github_webhook_received",
          "sync_status" => "syncing",
          "github_webhook_commit_sha" => attributes["commit_sha"],
          "github_webhook_received_at" => Time.current.iso8601
        ))
        task_id = run.metadata.to_h["auto_revision_task_id"]
        task = AutoRevisionTask.find_by(id: task_id)
        task&.update!(
          metadata: task.metadata.to_h.merge(
            "pipeline_stage" => "github_webhook_received",
            "github_webhook_commit_sha" => attributes["commit_sha"],
            "github_webhook_received_at" => Time.current.iso8601
          )
        )
        false
      end

      def ignored(reason, attributes)
        configuration.record!(status: "ignored", attributes: attributes.merge("reason" => reason))
        Result.new(status: "ignored", generation_run_id: nil, landing_page_id: nil, duplicate: false, reason:)
      end

      def failed(reason, attributes)
        configuration.record!(status: reason, failure: true, attributes: attributes.merge("error" => reason))
        Result.new(status: "failed", generation_run_id: nil, landing_page_id: nil, duplicate: false, reason:)
      end

      def diagnostic_attributes(delivery_id:, repository:, branch:, commit_sha:)
        {
          "event" => "push",
          "delivery_id" => delivery_id,
          "repository" => repository,
          "branch" => branch,
          "commit_sha" => commit_sha
        }.compact
      end

      def mark_enqueue_failure(run, key, error)
        receipts = Array(run.metadata.to_h["github_webhook_receipts"]).reject do |receipt|
          receipt.to_h["key"] == key
        end
        run.update!(
          error_message: error.message,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "github_webhook_waiting",
            "github_webhook_status" => "enqueue_failed",
            "lovable_error_code" => "webhook_enqueue_failed",
            "lovable_error_message" => error.message,
            "lovable_last_error_at" => Time.current.iso8601,
            "github_webhook_processing_key" => nil,
            "github_webhook_receipts" => receipts
          )
        )
      end
    end
  end
end

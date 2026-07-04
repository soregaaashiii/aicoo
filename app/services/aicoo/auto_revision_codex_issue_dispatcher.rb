module Aicoo
  class AutoRevisionCodexIssueDispatcher
    ELIGIBLE_STATUSES = %w[ready_for_codex queued sent_to_codex].freeze

    Result = Data.define(:processed_tasks, :created_issue_count, :skipped_count, :failed_count, :details) do
      def processed_count
        processed_tasks.size
      end
    end

    def call(tasks: nil, limit: 5)
      processed_tasks = []
      details = []
      created_issue_count = 0
      skipped_count = 0
      failed_count = 0

      candidate_tasks(tasks:, limit:).each do |task|
        processed_tasks << task
        detail = dispatch_task(task)
        details << detail

        case detail["status"]
        when "created", "already_created"
          created_issue_count += 1 if detail["status"] == "created"
        when "skipped"
          skipped_count += 1
        else
          failed_count += 1
        end
      end

      Result.new(processed_tasks:, created_issue_count:, skipped_count:, failed_count:, details:)
    end

    private

    def candidate_tasks(tasks:, limit:)
      explicit_tasks = Array(tasks).compact
      scope_tasks = AutoRevisionTask
        .includes(:business, :codex_submission)
        .where(status: ELIGIBLE_STATUSES, risk_level: "low")
        .by_priority
        .limit(limit)
        .to_a

      (explicit_tasks + scope_tasks)
        .select { |task| task.risk_level == "low" && task.status.in?(ELIGIBLE_STATUSES) }
        .uniq(&:id)
        .first(limit)
    end

    def dispatch_task(task)
      return detail_for(task, "skipped", "github_issue_already_created", issue_url: task.codex_submission.github_issue_url) if task.codex_submission&.github_issue_url.present?

      submission_result = Aicoo::CodexSubmissionBuilder.new(task).call
      if submission_result.reasons.any? || !submission_result.submission
        return detail_for(task, "skipped", "codex_submission_not_ready", reasons: submission_result.reasons)
      end

      issue_result = Aicoo::CodexGithubIssueBridge.new(submission_result.submission).call
      if issue_result.issue_url.present?
        task.mark_sent_to_codex! unless task.status == "sent_to_codex"
        detail_for(task, "created", "github_issue_created", issue_url: issue_result.issue_url, issue_number: issue_result.issue_number)
      else
        detail_for(task, "failed", "github_issue_not_created", message: issue_result.message)
      end
    rescue StandardError => e
      Rails.logger.warn("[AutoRevisionCodexIssueDispatcher] AutoRevisionTask##{task.id} failed: #{e.class} #{e.message}")
      detail_for(task, "failed", "exception", message: "#{e.class}: #{e.message}")
    end

    def detail_for(task, status, reason, extra = {})
      {
        "task_id" => task.id,
        "business_id" => task.business_id,
        "title" => task.title,
        "status" => status,
        "reason" => reason
      }.merge(extra.stringify_keys)
    end
  end
end

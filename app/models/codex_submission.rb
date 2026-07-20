class CodexSubmission < ApplicationRecord
  STATUSES = %w[draft ready submitted failed completed cancelled].freeze

  belongs_to :auto_revision_task
  belongs_to :business
  belongs_to :business_execution_profile

  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true
  validates :base_branch, presence: true
  validates :working_branch, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :ready, -> { where(status: "ready") }
  scope :draft, -> { where(status: "draft") }
  scope :failed, -> { where(status: "failed") }
  scope :with_pull_request, -> {
    where("response_payload ->> 'pull_request_url' IS NOT NULL OR response_payload ->> 'pr_url' IS NOT NULL")
  }

  after_commit :sync_lovable_publication, on: :update

  def mark_ready!
    update!(status: "ready")
  end

  def mark_submitted!(payload: {})
    update!(
      status: "submitted",
      submitted_at: Time.current,
      response_payload: response_payload.to_h.merge(payload.to_h)
    )
    mark_auto_revision_task_sent!
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  def mark_completed!(payload: {})
    update!(
      status: "completed",
      completed_at: Time.current,
      response_payload: response_payload.to_h.merge(payload.to_h)
    )
  end

  def retry!
    update!(status: "ready", error_message: nil)
  end

  def pr_url
    response_payload.to_h["pull_request_url"].presence || response_payload.to_h["pr_url"].presence
  end

  def github_issue_url
    response_payload.to_h["github_issue_url"].presence
  end

  def github_issue_number
    response_payload.to_h["github_issue_number"].presence
  end

  def pull_request_url
    pr_url
  end

  %w[pr_status review_status ci_status test_result merge_status deploy_status].each do |key|
    define_method(key) { tracking_value(key) }
  end

  def tracking_value(key)
    response_payload.to_h[key.to_s]
  end

  def update_tracking!(attributes)
    payload = attributes.to_h.compact_blank.stringify_keys
    normalized_payload = {
      "pull_request_url" => payload["pull_request_url"].presence || pr_url,
      "pr_url" => payload["pull_request_url"].presence || pr_url,
      "pr_status" => payload["pr_status"].presence,
      "review_status" => payload["review_status"].presence,
      "ci_status" => payload["ci_status"].presence,
      "test_result" => payload["test_result"].presence,
      "merge_status" => payload["merge_status"].presence,
      "deploy_status" => payload["deploy_status"].presence,
      "last_checked_at" => Time.current.iso8601,
      "tracking_updated_by" => payload["tracking_updated_by"].presence || "owner"
    }.compact_blank
    extra_payload = payload.except(
      "pull_request_url",
      "pr_status",
      "review_status",
      "ci_status",
      "test_result",
      "merge_status",
      "deploy_status",
      "tracking_updated_by"
    )
    normalized_payload["pr_created_at"] = Time.current.iso8601 if normalized_payload["pull_request_url"].present? && response_payload.to_h["pr_created_at"].blank?

    update!(response_payload: response_payload.to_h.merge(normalized_payload).merge(extra_payload))
    sync_execution_tracking!(normalized_payload)
  end

  def workflow_status
    return "failed" if status == "failed"
    return "completed" if status == "completed"
    return "deploy_waiting" if merge_status.to_s.in?(%w[merged merge済み]) && deploy_status.to_s.exclude?("deployed")
    return "merge_waiting" if pr_url.present? && (review_status.to_s.in?(%w[approved review済み]) || pr_status.to_s == "merge_waiting")
    return "pr_created" if pr_url.present?
    return "codex_executed" if status == "submitted" || github_issue_url.present?
    return "ready" if status == "ready"
    return "draft" if status == "draft"

    status
  end

  def workflow_status_label
    {
      "draft" => "準備不足",
      "ready" => "Codex投入待ち",
      "codex_executed" => "Codex実行済み",
      "pr_created" => "PR作成済み",
      "merge_waiting" => "merge待ち",
      "deploy_waiting" => "deploy待ち",
      "completed" => "完了",
      "failed" => "失敗",
      "cancelled" => "取消"
    }.fetch(workflow_status, workflow_status)
  end

  def external_handoff_url
    pr_url.presence || github_issue_url.presence
  end

  def external_handoff_label
    return "PRを開く" if pr_url.present?
    return "GitHub Issueを開く" if github_issue_url.present?

    "Codex投入準備"
  end

  def mark_merged!
    update_tracking!(
      merge_status: "merged",
      pr_status: "merged",
      tracking_updated_by: "owner",
      merged_at: Time.current.iso8601
    )
  end

  def mark_deployed!
    update_tracking!(
      deploy_status: "deployed",
      tracking_updated_by: "owner",
      deployed_at: Time.current.iso8601
    )
    mark_completed!(payload: { "deploy_status" => "deployed" }) unless status == "completed"
  end

  private

  def sync_lovable_publication
    return unless previous_changes.key?("response_payload") || previous_changes.key?("status")
    return unless auto_revision_task.metadata.to_h["lovable_generation_run_id"].present?

    Aicoo::Lovable::PublicationTracker.sync_for_submission(self)
  rescue StandardError => e
    Rails.logger.warn("[Lovable] Codex publication sync failed submission_id=#{id}: #{e.class}: #{e.message}")
  end

  def mark_auto_revision_task_sent!
    task = auto_revision_task
    return if task.status.in?(%w[sent_to_codex running completed succeeded partial_succeeded failed canceled])

    sent_time = Time.current
    task.update!(
      status: "sent_to_codex",
      sent_to_codex_at: task.sent_to_codex_at || sent_time
    )
    task.current_execution.update!(
      status: "sent_to_codex",
      prompt_snapshot: task.current_execution.prompt_snapshot.presence || task.codex_prompt_markdown,
      metadata: task.current_execution.metadata.to_h.merge(
        "codex_submission_id" => id,
        "github_issue_url" => github_issue_url,
        "codex_handoff_mode" => response_payload.to_h["codex_handoff_mode"].presence || "github_issue"
      ).compact_blank
    )
  rescue StandardError => e
    Rails.logger.warn("[CodexSubmission] AutoRevisionTask##{auto_revision_task_id} sent sync failed: #{e.class} #{e.message}")
  end

  def sync_execution_tracking!(payload)
    current_execution = auto_revision_task.current_execution
    current_execution.update!(
      pull_request_url: payload["pull_request_url"].presence || current_execution.pull_request_url,
      deploy_status: payload["deploy_status"].presence || current_execution.deploy_status,
      deploy_url: payload["deploy_url"].presence || current_execution.deploy_url,
      metadata: current_execution.metadata.to_h.merge(
        "codex_submission_id" => id,
        "codex_submission_status" => status,
        "codex_workflow_status" => workflow_status,
        "github_issue_url" => github_issue_url,
        "pull_request_url" => pr_url,
        "pr_status" => pr_status,
        "review_status" => review_status,
        "ci_status" => ci_status,
        "merge_status" => merge_status,
        "deploy_status" => deploy_status
      ).compact_blank
    )
  rescue StandardError => e
    Rails.logger.warn("[CodexSubmission] AutoRevisionTask##{auto_revision_task_id} tracking sync failed: #{e.class} #{e.message}")
  end
end

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

  def mark_ready!
    update!(status: "ready")
  end

  def mark_submitted!(payload: {})
    update!(
      status: "submitted",
      submitted_at: Time.current,
      response_payload: response_payload.to_h.merge(payload.to_h)
    )
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
    normalized_payload["pr_created_at"] = Time.current.iso8601 if normalized_payload["pull_request_url"].present? && response_payload.to_h["pr_created_at"].blank?

    update!(response_payload: response_payload.to_h.merge(normalized_payload))
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
end

class AutoRevisionExecution < ApplicationRecord
  STATUSES = %w[queued sent_to_codex running completed failed canceled].freeze

  belongs_to :auto_revision_task

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[queued sent_to_codex running]) }

  before_validation :set_defaults

  def finish!(status:, result_summary: nil, error_message: nil, commit_sha: nil, pull_request_url: nil, deploy_url: nil, deploy_status: nil)
    update!(
      status:,
      finished_at: Time.current,
      result_summary: result_summary.presence || self.result_summary,
      error_message: error_message.presence || self.error_message,
      commit_sha: commit_sha.presence || self.commit_sha,
      pull_request_url: pull_request_url.presence || self.pull_request_url,
      deploy_url: deploy_url.presence || self.deploy_url,
      deploy_status: deploy_status.presence || self.deploy_status
    )
  end

  private

  def set_defaults
    self.status ||= "queued"
    self.metadata ||= {}
  end
end

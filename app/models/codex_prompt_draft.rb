class CodexPromptDraft < ApplicationRecord
  STATUSES = %w[draft approved copied executed rejected].freeze
  RISK_LEVELS = %w[low medium high].freeze
  DEFAULT_VERIFICATION_COMMANDS = [
    "bin/rails test",
    "bin/rails zeitwerk:check",
    "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop"
  ].freeze

  belongs_to :action_candidate
  belongs_to :business, optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :verification_commands, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_status, ->(status) { status.present? ? where(status:) : all }

  def self.from_action_candidate(action_candidate)
    find_by(action_candidate:) ||
      Aicoo::CodexPromptDraftBuilder.new(action_candidate).call
  end

  def approve!
    update!(status: "approved")
  end

  def reject!
    update!(status: "rejected")
  end

  def mark_copied!
    update!(status: "copied", metadata: metadata.to_h.merge("copied_at" => Time.current.iso8601))
  end

  def mark_executed!
    update!(status: "executed", metadata: metadata.to_h.merge("executed_at" => Time.current.iso8601))
  end
end

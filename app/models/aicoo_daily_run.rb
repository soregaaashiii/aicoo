class AicooDailyRun < ApplicationRecord
  STATUSES = %w[pending running success succeeded failed partial_failed stuck skipped].freeze
  SOURCES = %w[cron catch_up manual].freeze
  SUCCESS_STATUSES = %w[success succeeded].freeze

  validates :target_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :retry_count, :analytics_fetch_count, :snapshot_count, :insight_generated_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :updated_calibration_count, :calibration_log_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :pending_calibration_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  has_many :meta_evaluation_snapshots, dependent: :nullify
  has_many :aicoo_daily_run_steps, dependent: :destroy
  has_one :auto_revision_queue_run, dependent: :destroy

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }
  scope :running, -> { where(status: "running") }
  scope :successful, -> { where(status: SUCCESS_STATUSES) }
  scope :retryable, -> { where(status: %w[failed partial_failed stuck skipped]) }

  def running?
    status == "running"
  end

  def succeeded?
    SUCCESS_STATUSES.include?(status)
  end

  def failed?
    %w[failed partial_failed stuck].include?(status)
  end
end

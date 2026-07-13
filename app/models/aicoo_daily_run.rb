class AicooDailyRun < ApplicationRecord
  STATUSES = %w[pending running success succeeded failed partial_failed stuck skipped duplicate_skipped].freeze
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
  scope :actual_runs, -> { where.not(status: %w[skipped duplicate_skipped]) }
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

  def running_duration_seconds
    return 0 unless running? && started_at

    (Time.current - started_at).to_i
  end

  def running_duration_label
    seconds = running_duration_seconds
    return "-" if seconds.zero?

    minutes = seconds / 60
    return "#{seconds}秒" if minutes.zero?

    hours = minutes / 60
    remaining_minutes = minutes % 60
    return "#{minutes}分" if hours.zero?

    "#{hours}時間#{remaining_minutes}分"
  end

  def current_step
    aicoo_daily_run_steps.where(status: "running").order(started_at: :desc, created_at: :desc).first ||
      aicoo_daily_run_steps.order(started_at: :desc, created_at: :desc).first
  end
end

class AicooDailyRunStep < ApplicationRecord
  STATUSES = %w[pending running success failed skipped].freeze
  PRIMARY_STEP_NAMES = %w[analytics_fetch datahub_collect business_metrics_import action_generation insight_generation].freeze
  RECOVERABLE_STEP_NAMES = %w[calibration owner_task_digest action_result_evaluation score_snapshot].freeze
  RECOVERY_STATUSES = %w[success failed skipped].freeze
  SLOW_THRESHOLD_SECONDS = 60

  belongs_to :aicoo_daily_run

  validates :step_name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :last_recovery_status, inclusion: { in: RECOVERY_STATUSES }, allow_blank: true

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }
  scope :failed, -> { where(status: "failed") }
  scope :skipped, -> { where(status: "skipped") }
  scope :successful, -> { where(status: "success") }

  def primary?
    PRIMARY_STEP_NAMES.include?(step_name)
  end

  def recoverable?
    RECOVERABLE_STEP_NAMES.include?(step_name)
  end

  def recovery_needed?
    recoverable? && status.in?(%w[failed skipped])
  end

  def slow?(average_duration: nil)
    duration = duration_seconds.to_d
    return false if duration.zero?
    return true if duration >= SLOW_THRESHOLD_SECONDS

    average_duration.present? && average_duration.to_d.positive? && duration >= (average_duration.to_d * 2)
  end
end

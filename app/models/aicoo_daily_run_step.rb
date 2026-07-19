class AicooDailyRunStep < ApplicationRecord
  STATUSES = %w[pending running success failed skipped].freeze
  PRIMARY_STEP_NAMES = %w[analytics_fetch datahub_collect business_metrics_import suelog_database_health_check suelog_candidate_generation article_opportunity_analysis action_generation insight_generation].freeze
  RECOVERABLE_STEP_NAMES = %w[
    calibration
    article_opportunity_analysis
    business_metrics_import
    owner_task_digest
    owner_execution_queue
    action_result_evaluation
    score_snapshot
    data_preparation_queue
    meta_evaluation_snapshot
    source_app_diff_detection
    activity_log_evaluation_queue_build
    business_playbook_update
    traffic_channel_recording
    system_mode_snapshot
  ].freeze
  RECOVERY_STATUSES = %w[success failed skipped].freeze
  SLOW_THRESHOLD_SECONDS = 60
  MAX_RECOVERY_ATTEMPTS = 3
  RECOVERY_COOLDOWN = 5.minutes

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

  def recovery_available?
    recovery_needed? && !recovery_locked? && !recovery_cooldown_active? && !recovery_limit_reached?
  end

  def recovery_cooldown_active?
    last_recovery_at.present? && last_recovery_at > RECOVERY_COOLDOWN.ago
  end

  def recovery_limit_reached?
    recovery_attempt_count >= MAX_RECOVERY_ATTEMPTS && last_recovery_status == "failed"
  end

  def recovery_state_label
    return "再実行不可" unless recoverable?
    return "Locked" if recovery_locked?
    return "Limit Reached" if recovery_limit_reached?
    return "Cooldown" if recovery_cooldown_active?
    return "Available" if recovery_needed?

    "再実行可能"
  end

  def recovery_unavailable_reason
    return "Recovery is already running" if recovery_locked?
    return "Recovery limit reached" if recovery_limit_reached?
    return "Recovery cooldown active" if recovery_cooldown_active?
    "#{step_name} step は再実行不可です" unless recoverable?
  end

  def slow?(average_duration: nil)
    duration = duration_seconds.to_d
    return false if duration.zero?
    return true if duration >= SLOW_THRESHOLD_SECONDS

    average_duration.present? && average_duration.to_d.positive? && duration >= (average_duration.to_d * 2)
  end
end

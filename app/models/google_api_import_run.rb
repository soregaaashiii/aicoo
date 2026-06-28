class GoogleApiImportRun < ApplicationRecord
  STATUSES = %w[queued running success failed].freeze
  DEFAULT_FETCH_DAYS = 28
  MAX_INCREMENTAL_FETCH_DAYS = 28

  belongs_to :business

  validates :status, inclusion: { in: STATUSES }
  validates :fetched_days, numericality: { only_integer: true, greater_than: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :running, -> { where(status: %w[queued running]) }
  scope :successful, -> { where(status: "success") }

  def self.running_for?(business)
    running.exists?(business:)
  end

  def self.latest_for(business)
    where(business:).recent.first
  end

  def self.next_fetch_days_for(business, full_fetch: false, today: Date.current)
    return DEFAULT_FETCH_DAYS if full_fetch

    latest_success = where(business:).successful.recent.first
    return DEFAULT_FETCH_DAYS unless latest_success&.finished_at

    latest_end_date = latest_success.metadata["end_date"].presence
    base_date = latest_end_date ? Date.iso8601(latest_end_date) : latest_success.finished_at.to_date
    days_since_success = (today.to_date - base_date).to_i
    days_since_success.clamp(1, MAX_INCREMENTAL_FETCH_DAYS)
  rescue Date::Error
    DEFAULT_FETCH_DAYS
  end

  def running?
    %w[queued running].include?(status)
  end

  def failed?
    status == "failed"
  end

  def succeeded?
    status == "success"
  end

  def status_label
    case status
    when "queued", "running"
      "実行中"
    when "success"
      "成功"
    when "failed"
      "失敗"
    else
      "未実行"
    end
  end

  def mark_running!
    update!(status: "running", started_at: started_at.presence || Time.current)
  end

  def mark_success!(result)
    finished = Time.current
    update!(
      status: "success",
      finished_at: finished,
      duration_seconds: duration_from(finished),
      updated_metric_count: result.metric_count,
      error_message: nil,
      metadata: metadata.merge(
        "imported_source_labels" => result.imported_source_labels,
        "start_date" => result.start_date.to_s,
        "end_date" => result.end_date.to_s
      )
    )
  end

  def mark_failed!(error)
    finished = Time.current
    update!(
      status: "failed",
      finished_at: finished,
      duration_seconds: duration_from(finished),
      error_message: error.message
    )
  end

  private

  def duration_from(finished)
    return unless started_at

    (finished - started_at).round(2)
  end
end

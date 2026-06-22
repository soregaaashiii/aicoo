class AicooDailyRun < ApplicationRecord
  STATUSES = %w[pending running succeeded failed].freeze

  validates :target_date, presence: true
  validates :status, inclusion: { in: STATUSES }

  has_many :meta_evaluation_snapshots, dependent: :nullify

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }
  scope :running, -> { where(status: "running") }

  def running?
    status == "running"
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end
end

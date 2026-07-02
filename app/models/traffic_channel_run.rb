class TrafficChannelRun < ApplicationRecord
  STATUSES = %w[running success warning failed skipped].freeze
  SOURCES = %w[daily_run manual import].freeze

  belongs_to :business, optional: true

  validates :channel_key, :ran_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :sessions, :clicks, :conversions, :revenue_yen, :cost_yen, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :hours_spent, numericality: { greater_than_or_equal_to: 0 }

  scope :today, -> { where(ran_at: Time.zone.today.all_day) }
  scope :recent, -> { order(ran_at: :desc, created_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }

  def inflow_count
    sessions.to_i.positive? ? sessions.to_i : clicks.to_i
  end

  def roi
    return nil if cost_yen.to_i.zero?

    revenue_yen.to_d / cost_yen.to_d
  end
end

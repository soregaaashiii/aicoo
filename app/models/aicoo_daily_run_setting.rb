class AicooDailyRunSetting < ApplicationRecord
  DEFAULT_TIMEZONE = "Asia/Tokyo"

  validates :run_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :run_minute, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 59 }
  validates :timezone, presence: true
  validates :max_retry_per_day, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  def self.current
    first_or_create!
  end

  def scheduled_time_for(date = Date.current)
    zone = Time.find_zone(timezone.presence || DEFAULT_TIMEZONE) || Time.find_zone(DEFAULT_TIMEZONE)
    zone.local(date.year, date.month, date.day, run_hour, run_minute)
  end
end

class AicooAutoRevisionSetting < ApplicationRecord
  DEFAULTS = {
    enabled: false,
    max_tasks_per_run: 5,
    minimum_final_score: 1_000,
    allow_medium_risk: true,
    created_by_system: true
  }.freeze

  validates :max_tasks_per_run, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 50 }
  validates :minimum_final_score, numericality: { greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!(DEFAULTS)
  end
end

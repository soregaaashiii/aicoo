class AicooLabSetting < ApplicationRecord
  validates :monthly_budget_yen, :minimum_sample_pv, :hourly_cost_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!
  end
end

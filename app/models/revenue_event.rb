class RevenueEvent < ApplicationRecord
  EVENT_TYPES = %w[revenue expense].freeze

  belongs_to :business

  enum :event_type, {
    revenue: "revenue",
    expense: "expense"
  }, validate: true

  validates :occurred_on, presence: true
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
end

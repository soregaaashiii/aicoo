class BusinessService < ApplicationRecord
  STATUSES = %w[planning building live production paused archived].freeze

  belongs_to :business

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(updated_at: :desc, created_at: :desc) }

  def display_url
    url.presence || domain.presence || "-"
  end
end

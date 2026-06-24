class ExploreDataSource < ApplicationRecord
  SOURCE_TYPES = %w[
    google_trends
    clarity
    reddit
    youtube
    x
    google_business_profile
  ].freeze
  STATUSES = %w[active inactive error].freeze

  has_many :explore_observations, dependent: :destroy

  before_validation :set_defaults

  validates :name, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :enabled, -> { where(enabled: true) }
  scope :active, -> { where(status: "active") }

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.status = "inactive" if status.blank?
  end
end

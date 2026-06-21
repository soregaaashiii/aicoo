class DataSource < ApplicationRecord
  SOURCE_TYPES = %w[gsc ga4 serp market_research sales custom].freeze
  STATUSES = %w[active archived].freeze

  belongs_to :business
  has_many :data_imports, dependent: :destroy

  validates :name, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_defaults

  private

  def set_defaults
    self.status = "active" if status.blank?
    self.source_type = "custom" if source_type.blank?
  end
end

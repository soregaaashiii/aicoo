class DataImport < ApplicationRecord
  belongs_to :data_source
  belongs_to :aicoo_analytics_site, optional: true
  has_one :business, through: :data_source

  validates :filename, :imported_at, presence: true
  validates :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(imported_at: :desc, created_at: :desc) }
end

class ExploreImportLog < ApplicationRecord
  IMPORT_FORMATS = %w[csv json text].freeze

  validates :source_type, inclusion: { in: ExploreDataSource::SOURCE_TYPES }
  validates :import_format, inclusion: { in: IMPORT_FORMATS }
  validates :imported_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
end

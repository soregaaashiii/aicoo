class SerpAnalysis < ApplicationRecord
  SEARCH_ENGINES = %w[google].freeze
  DEVICES = %w[desktop mobile].freeze

  belongs_to :business
  belongs_to :data_import, optional: true
  has_many :serp_results, dependent: :destroy

  validates :keyword, :analyzed_at, presence: true
  validates :search_engine, inclusion: { in: SEARCH_ENGINES }
  validates :device, inclusion: { in: DEVICES }, allow_blank: true
  validates :competition_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :result_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end

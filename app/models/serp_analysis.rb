class SerpAnalysis < ApplicationRecord
  SEARCH_ENGINES = %w[google].freeze
  DEVICES = %w[desktop mobile].freeze
  STATUSES = %w[running success failed].freeze

  belongs_to :business
  belongs_to :data_import, optional: true
  has_many :serp_results, dependent: :destroy

  validates :keyword, :analyzed_at, presence: true
  validates :search_engine, inclusion: { in: SEARCH_ENGINES }
  validates :device, inclusion: { in: DEVICES }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :competition_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :result_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :running, -> { where(status: "running") }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }

  def running?
    status == "running"
  end

  def successful?
    status == "success"
  end

  def failed?
    status == "failed"
  end
end

class AicooDataSnapshot < ApplicationRecord
  SOURCE_TYPES = %w[ga4 gsc landing_page revenue_execution].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, presence: true
  validates :captured_at, presence: true

  before_validation :set_defaults

  scope :today, -> { where(captured_at: Time.current.all_day) }
  scope :recent, -> { order(captured_at: :desc, created_at: :desc) }

  def source_record
    case source_type
    when "ga4", "gsc"
      DataImport.find_by(id: source_id)
    when "landing_page"
      AicooLabLandingPage.find_by(id: source_id)
    when "revenue_execution"
      AicooRevenueExecution.find_by(id: source_id)
    end
  end

  private

  def set_defaults
    self.captured_at ||= Time.current
    self.payload ||= {}
  end
end

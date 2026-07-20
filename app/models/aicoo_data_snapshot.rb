class AicooDataSnapshot < ApplicationRecord
  SOURCE_TYPES = %w[ga4 gsc landing_page revenue_execution article_analytics].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, presence: true
  validates :captured_at, presence: true

  before_validation :set_defaults
  after_commit :refresh_lovable_landing_page_learning, on: :create, if: :google_metric_snapshot?

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
    when "article_analytics"
      ::Suelog::Article.find_by(id: source_id) if defined?(::Suelog::Article)
    end
  rescue StandardError
    nil
  end

  private

  def google_metric_snapshot?
    source_type.in?(%w[ga4 gsc])
  end

  def refresh_lovable_landing_page_learning
    business = source_record&.business
    return unless business

    business.aicoo_lab_landing_pages.where(generation_source: "lovable").find_each do |landing_page|
      Aicoo::Lovable::LearningRefresher.call(landing_page)
    end
  rescue StandardError => e
    Rails.logger.warn("[Lovable] metric snapshot learning refresh failed snapshot_id=#{id}: #{e.class}: #{e.message}")
  end

  def set_defaults
    self.captured_at ||= Time.current
    self.payload ||= {}
  end
end

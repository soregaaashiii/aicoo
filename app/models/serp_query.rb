class SerpQuery < ApplicationRecord
  CATEGORIES = %w[
    existing_business
    keyword_discovery
    new_business
    competitor
    trend
    reddit
    x
    youtube
    producthunt
  ].freeze
  STATUSES = %w[active paused archived].freeze

  belongs_to :business

  validates :query, presence: true
  validates :normalized_query, presence: true, uniqueness: { scope: :business_id }
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :daily_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :country, :language, presence: true

  before_validation :set_defaults
  before_validation :normalize_query

  scope :active, -> { where(status: "active") }
  scope :enabled, -> { where(enabled: true, status: "active") }
  scope :disabled, -> { where(enabled: false) }
  scope :by_priority, -> { order(priority: :asc, last_run_at: :asc, created_at: :asc) }
  scope :due_today, -> {
    where("last_run_at IS NULL OR last_run_at < ?", Time.zone.today.beginning_of_day)
  }

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkc).strip.downcase.gsub(/\s+/, " ")
  end

  def self.parse_queries(raw)
    raw.to_s.split(/[\n,、]/).map(&:strip).compact_blank.uniq { |query| normalize(query) }
  end

  def runnable_today?
    return false unless enabled?
    return false unless status == "active"
    return false if daily_limit.to_i <= 0

    today_run_count < daily_limit.to_i
  end

  def recently_successful?(window: 24.hours)
    last_success_at.present? && last_success_at > window.ago
  end

  def today_run_count
    business.serp_analyses.where(keyword: query, analyzed_at: Time.zone.today.all_day).count
  end

  def record_run!
    update!(last_run_at: Time.current)
  end

  def record_success!(candidate_count: 0)
    update!(
      last_success_at: Time.current,
      success_count: success_count.to_i + 1,
      total_candidates_generated: total_candidates_generated.to_i + candidate_count.to_i
    )
  end

  def record_failure!
    update!(failure_count: failure_count.to_i + 1)
  end

  def toggle!
    update!(enabled: !enabled?)
  end

  def pause!
    update!(status: "paused", enabled: false)
  end

  def resume!
    update!(status: "active", enabled: true)
  end

  def archive!
    update!(status: "archived", enabled: false)
  end

  private

  def set_defaults
    self.category = "existing_business" if category.blank?
    self.status = "active" if status.blank?
    self.country = "jp" if country.blank?
    self.language = "ja" if language.blank?
    self.priority = 100 if priority.blank?
    self.daily_limit = 1 if daily_limit.blank?
    self.enabled = true if enabled.nil?
  end

  def normalize_query
    self.query = query.to_s.strip
    self.normalized_query = self.class.normalize(query)
  end
end

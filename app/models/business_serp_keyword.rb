class BusinessSerpKeyword < ApplicationRecord
  SOURCES = %w[manual ai_suggested gsc serp_related imported].freeze
  STATUSES = %w[pending active paused archived excluded].freeze

  belongs_to :business

  validates :keyword, presence: true
  validates :normalized_keyword, presence: true, uniqueness: { scope: :business_id }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :priority_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :opportunity_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :confidence, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  before_validation :normalize_keyword

  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :excluded, -> { where(status: "excluded") }
  scope :fetchable, -> { active.order(priority_score: :desc, last_checked_at: :asc, created_at: :asc) }

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkc).strip.downcase.gsub(/\s+/, " ")
  end

  def self.parse_keywords(raw)
    raw.to_s.split(/[\n,、]/).map(&:strip).compact_blank.uniq { |keyword| normalize(keyword) }
  end

  def activate!
    update!(status: "active")
  end

  def pause!
    update!(status: "paused")
  end

  def archive!
    update!(status: "archived")
  end

  def exclude!(reason: nil)
    update!(
      status: "excluded",
      reason: reason.presence || self.reason.presence || "除外キーワード",
      metadata_json: metadata_json.to_h.merge("excluded_at" => Time.current.iso8601)
    )
  end

  def restore!
    update!(status: "active")
  end

  private

  def normalize_keyword
    self.keyword = keyword.to_s.strip
    self.normalized_keyword = self.class.normalize(keyword)
  end
end

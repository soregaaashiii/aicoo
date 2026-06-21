class AnalyticsSourceSetting < ApplicationRecord
  SOURCE_TYPES = %w[ga4 gsc].freeze

  has_many :analytics_fetch_runs, dependent: :destroy
  belongs_to :aicoo_analytics_site, optional: true

  before_validation :set_defaults

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :name, presence: true
  validates :fetch_days, numericality: { only_integer: true, greater_than: 0 }
  validates :property_id, presence: true, if: -> { source_type == "ga4" }
  validates :site_url, presence: true, if: -> { source_type == "gsc" }
  validate :unique_enabled_gsc_site_url
  validate :unique_enabled_ga4_property_id

  scope :recent, -> { order(created_at: :desc) }

  def latest_fetch_run
    analytics_fetch_runs.recent.first
  end

  def duplicate_enabled?
    duplicate_enabled_scope.exists?
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.fetch_days = 28 if fetch_days.blank?
  end

  def unique_enabled_gsc_site_url
    return unless enabled? && source_type == "gsc" && site_url.present?

    errors.add(:site_url, "同じGSCサイトURLの有効設定が既に存在します") if duplicate_enabled_scope.exists?
  end

  def unique_enabled_ga4_property_id
    return unless enabled? && source_type == "ga4" && property_id.present?

    errors.add(:property_id, "同じGA4プロパティIDの有効設定が既に存在します") if duplicate_enabled_scope.exists?
  end

  def duplicate_enabled_scope
    scope = self.class.where(source_type:, enabled: true)
    scope = scope.where.not(id:) if persisted?

    case source_type
    when "gsc"
      site_url.present? ? scope.where(site_url:) : scope.none
    when "ga4"
      property_id.present? ? scope.where(property_id:) : scope.none
    else
      scope.none
    end
  end
end

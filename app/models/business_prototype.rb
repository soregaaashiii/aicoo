require "uri"

class BusinessPrototype < ApplicationRecord
  EXTERNAL_LANDING_PAGE_ROLE = "external_landing_page".freeze
  LEGACY_LANDING_PAGE_ROLE = "external_lp_integration".freeze
  LANDING_PAGE_ROLES = [ EXTERNAL_LANDING_PAGE_ROLE, LEGACY_LANDING_PAGE_ROLE ].freeze
  PROTOTYPE_TYPES = %w[github url lovable figma local render other].freeze
  STATUSES = %w[active archived].freeze
  ANALYSIS_STATUSES = %w[pending queued analyzing succeeded failed].freeze
  URL_TYPES = %w[github url lovable figma render].freeze

  belongs_to :business

  validates :prototype_type, inclusion: { in: PROTOTYPE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :analysis_status, inclusion: { in: ANALYSIS_STATUSES }
  validates :location, presence: true
  validate :location_matches_prototype_type

  before_validation :set_defaults

  scope :active, -> { where(status: "active") }
  scope :recent, -> { order(updated_at: :desc) }
  scope :external_landing_pages, -> {
    where("metadata ->> 'role' IN (?)", LANDING_PAGE_ROLES).recent
  }

  def external_landing_page?
    metadata.to_h["role"].in?(LANDING_PAGE_ROLES)
  end

  def landing_page_name
    metadata.to_h["lp_name"].presence || name.presence || "LP ##{id}"
  end

  def landing_page_url
    metadata.to_h["lp_url"].presence || metadata.to_h["lp_public_url"].presence ||
      (location if prototype_type == "url")
  end

  def landing_page_repository_url
    metadata.to_h["lp_repository_url"].presence || metadata.to_h["lp_source_repository_url"].presence ||
      (location if prototype_type == "github")
  end

  def landing_page_branch
    metadata.to_h["lp_branch"].presence || metadata.to_h["lp_source_branch"].presence || "main"
  end

  def landing_page_source_type
    metadata.to_h["lp_source_type"].presence || prototype_type
  end

  def landing_page_public_status
    metadata.to_h["lp_public_status"].presence || "draft"
  end

  def landing_page_public_status_label
    { "draft" => "下書き", "published" => "公開", "paused" => "一時停止" }.fetch(
      landing_page_public_status,
      landing_page_public_status
    )
  end

  def landing_page_ga4_path
    metadata.to_h["ga4_page_path"]
  end

  def landing_page_sync_status
    metadata.to_h["sync_status"].presence || "not_synced"
  end

  def landing_page_sync_status_label
    {
      "not_synced" => "未同期",
      "task_created" => "同期タスク作成済み",
      "syncing" => "同期中",
      "synced" => "同期済み",
      "failed" => "同期失敗"
    }.fetch(landing_page_sync_status, landing_page_sync_status)
  end

  def landing_page_last_sync_at
    Time.zone.parse(metadata.to_h["last_sync_at"].to_s) if metadata.to_h["last_sync_at"].present?
  rescue ArgumentError
    nil
  end

  def landing_page_conversion_rate
    metadata.to_h["current_conversion_rate"].presence&.to_d
  end

  def display_name
    name.presence || prototype_type_label
  end

  def prototype_type_label
    {
      "github" => "GitHub",
      "url" => "URL",
      "lovable" => "Lovable",
      "figma" => "Figma",
      "local" => "ローカル",
      "render" => "Render",
      "other" => "その他"
    }.fetch(prototype_type, prototype_type.to_s.humanize)
  end

  private

  def set_defaults
    self.status = "active" if status.blank?
    self.analysis_status = "pending" if analysis_status.blank?
    self.analysis = {} if analysis.blank?
    self.metadata = {} if metadata.blank?
  end

  def location_matches_prototype_type
    return unless prototype_type.in?(URL_TYPES)

    uri = URI.parse(location.to_s)
    errors.add(:location, "はhttp(s) URLを入力してください") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:location, "は有効なURLを入力してください")
  end
end

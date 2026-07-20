require "uri"

class BusinessPrototype < ApplicationRecord
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

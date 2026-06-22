class AicooGoogleCredential < ApplicationRecord
  has_many :analytics_source_settings, foreign_key: :google_credential_id, dependent: :nullify

  before_validation :set_defaults

  validates :name, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :recent, -> { order(created_at: :desc) }

  def self.default
    enabled.recent.first
  end

  def connected?
    client_id.present? && client_secret.present? && refresh_token.present?
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end

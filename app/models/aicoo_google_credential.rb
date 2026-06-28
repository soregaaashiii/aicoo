class AicooGoogleCredential < ApplicationRecord
  has_many :analytics_source_settings, foreign_key: :google_credential_id, dependent: :nullify

  before_validation :set_defaults
  before_save :invalidate_oauth_tokens_when_client_id_changes

  validates :name, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :recent, -> { order(created_at: :desc) }

  def self.default
    enabled.recent.first
  end

  def connected?
    client_id.present? && client_secret.present? && refresh_token.present?
  end

  def reauthentication_required?
    client_id.present? && client_secret.present? && refresh_token.blank?
  end

  def oauth_project_number
    client_id.to_s.split("-").first if client_id.to_s.match?(/\A\d+-/)
  end

  def effective_google_cloud_project_id
    google_cloud_project_id.presence ||
      ENV["GOOGLE_CLOUD_PROJECT"].presence ||
      ENV["GOOGLE_PROJECT_ID"].presence ||
      oauth_project_number
  end

  def env_client_id_mismatch?
    client_id.present? && ENV["GOOGLE_CLIENT_ID"].present? && client_id != ENV["GOOGLE_CLIENT_ID"]
  end

  def env_project_id_mismatch?
    google_cloud_project_id.present? &&
      env_google_cloud_project_id.present? &&
      google_cloud_project_id != env_google_cloud_project_id
  end

  def env_google_cloud_project_id
    ENV["GOOGLE_CLOUD_PROJECT"].presence || ENV["GOOGLE_PROJECT_ID"].presence
  end

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end

  def invalidate_oauth_tokens_when_client_id_changes
    return unless persisted? && will_save_change_to_client_id?
    return if will_save_change_to_refresh_token? && refresh_token.present?

    self.refresh_token = nil
    self.access_token = nil
    self.token_expires_at = nil
    self.google_account_email = nil
    self.connected_at = nil
  end
end

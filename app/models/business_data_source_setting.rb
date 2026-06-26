class BusinessDataSourceSetting < ApplicationRecord
  CONNECTION_STATUSES = %w[unlinked linked needs_attention error].freeze
  CONNECTION_STATUS_LABELS = {
    "unlinked" => "未紐付け",
    "linked" => "紐付け済み",
    "needs_attention" => "要確認",
    "error" => "エラー"
  }.freeze

  belongs_to :business
  belongs_to :data_source_cost_profile, foreign_key: :source_key, primary_key: :source_key, inverse_of: :business_data_source_settings, optional: true

  validates :source_key, presence: true
  validates :source_key, uniqueness: { scope: :business_id }
  validates :connection_status, inclusion: { in: CONNECTION_STATUSES }

  before_validation :set_defaults
  before_save :stamp_last_connected_at

  def self.enabled_for?(business, source_key)
    setting = find_by(business:, source_key:)
    setting.nil? ? true : setting.enabled?
  end

  def self.for_business_and_source(business, source_key)
    find_by(business:, source_key:) || new(business:, source_key:)
  end

  def linked?
    connection_status == "linked"
  end

  def connection_status_label
    CONNECTION_STATUS_LABELS.fetch(connection_status, connection_status)
  end

  def connection_status_level
    case connection_status
    when "linked" then "healthy"
    when "needs_attention" then "warning"
    when "error" then "critical"
    else "attention"
    end
  end

  def connection_summary
    [
      connection_field_value("site_url").presence,
      connection_field_value("property_id").presence,
      connection_field_value("keyword").presence,
      connection_field_value("search_query").presence,
      connection_field_value("customer_id").presence,
      connection_field_value("ad_account_id").presence,
      connection_field_value("project_id").presence,
      property_identifier.presence,
      external_account_id.presence,
      endpoint_url.presence,
      credential_reference.presence
    ].compact.first || "詳細未設定"
  end

  def connection_fields
    Aicoo::DataSourceFieldRegistry.business_connection_fields(source_key)
  end

  def connection_field_values
    metadata.fetch("connection_fields", {})
  end

  def connection_field_value(key)
    connection_field_values[key.to_s]
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.connection_status = "unlinked" if connection_status.blank?
    self.metadata = {} if metadata.blank?
  end

  def stamp_last_connected_at
    return unless connection_status == "linked"
    return unless will_save_change_to_connection_status? || last_connected_at.blank?

    self.last_connected_at = Time.current
  end
end

class SourceAppConnection < ApplicationRecord
  CONNECTION_TYPES = %w[same_database external_api csv].freeze
  STATUSES = %w[active inactive error].freeze

  belongs_to :business
  has_many :source_app_diff_rules, dependent: :destroy

  validates :name, :source_app, :connection_type, :status, presence: true
  validates :source_app, uniqueness: { scope: :business_id }
  validates :connection_type, inclusion: { in: CONNECTION_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :enabled, -> { where(enabled: true) }
  scope :active, -> { where(status: "active") }

  def self.ensure_suelog_defaults!
    business = Business.real_businesses.find_by(name: "吸えログ")
    return unless business

    connection = find_or_create_by!(business:, source_app: "suelog") do |record|
      record.name = "吸えログ"
      record.connection_type = "same_database"
      record.status = "active"
      record.enabled = true
    end

    unless connection.settings.to_h["database_connection"] == "suelog"
      connection.update!(settings: connection.settings.to_h.merge("database_connection" => "suelog"))
    end

    SourceAppDiffRule.ensure_suelog_defaults!(connection)
    connection
  end
end

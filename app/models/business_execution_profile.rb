class BusinessExecutionProfile < ApplicationRecord
  REPOSITORY_TYPES = %w[rails nextjs static_site wordpress api other].freeze
  DEFAULT_FORBIDDEN_PATTERNS = [
    "db:drop",
    "db:reset",
    "drop database"
  ].freeze

  belongs_to :business

  validates :business_id, uniqueness: true
  validates :repository_type, inclusion: { in: REPOSITORY_TYPES }
  validates :default_branch, presence: true

  before_validation :set_defaults

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc) }

  def forbidden_pattern_lines
    forbidden_patterns.to_s.lines.map(&:strip).reject(&:blank?)
  end

  def display_repository_name
    repository_name.presence || github_repository.presence || repository_path.presence || "-"
  end

  private

  def set_defaults
    self.repository_type = "other" if repository_type.blank?
    self.default_branch = "main" if default_branch.blank?
    self.active = true if active.nil?
    return if forbidden_patterns.present?

    self.forbidden_patterns = DEFAULT_FORBIDDEN_PATTERNS.join("\n")
  end
end
